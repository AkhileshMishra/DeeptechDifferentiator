#!/bin/bash
# Healthcare Imaging MLOps Platform - Monitoring Script
# Provides real-time monitoring of pipeline executions and system health

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Load configuration
load_config() {
    if [ -f "${TERRAFORM_DIR}/deployment-outputs.json" ]; then
        OUTPUTS=$(cat "${TERRAFORM_DIR}/deployment-outputs.json")
    else
        echo -e "${RED}Error: deployment-outputs.json not found${NC}"
        exit 1
    fi
}

# Display header
show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Healthcare Imaging MLOps Platform - System Monitor            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Last updated: $(date)"
    echo ""
}

# Monitor SageMaker Pipeline Executions
monitor_pipelines() {
    echo -e "${YELLOW}═══ SageMaker Pipeline Executions ═══${NC}"
    
    PIPELINE_NAME=$(echo $OUTPUTS | jq -r '.sagemaker_pipeline_name.value // "healthcare-imaging-mlops-pneumonia-pipeline"')
    
    aws sagemaker list-pipeline-executions \
        --pipeline-name $PIPELINE_NAME \
        --sort-by CreationTime \
        --sort-order Descending \
        --max-results 5 \
        --query 'PipelineExecutionSummaries[*].[PipelineExecutionArn,PipelineExecutionStatus,CreationTime]' \
        --output table 2>/dev/null || echo "No pipeline executions found"
    
    echo ""
}

# Monitor Lambda Function Metrics
monitor_lambda() {
    echo -e "${YELLOW}═══ Lambda Function Metrics (Last Hour) ═══${NC}"
    
    START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    for func in image-ingestion pipeline-trigger model-evaluation; do
        FUNC_NAME="healthcare-imaging-mlops-${func}"
        
        INVOCATIONS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/Lambda \
            --metric-name Invocations \
            --dimensions Name=FunctionName,Value=$FUNC_NAME \
            --start-time $START_TIME \
            --end-time $END_TIME \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        ERRORS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/Lambda \
            --metric-name Errors \
            --dimensions Name=FunctionName,Value=$FUNC_NAME \
            --start-time $START_TIME \
            --end-time $END_TIME \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$ERRORS" == "None" ]; then ERRORS="0"; fi
        if [ "$INVOCATIONS" == "None" ]; then INVOCATIONS="0"; fi
        
        if [ "$ERRORS" == "0" ]; then
            STATUS="${GREEN}●${NC}"
        else
            STATUS="${RED}●${NC}"
        fi
        
        printf "  %b %-30s Invocations: %-8s Errors: %s\n" "$STATUS" "$func" "$INVOCATIONS" "$ERRORS"
    done
    
    echo ""
}

# Monitor DynamoDB Tables
monitor_dynamodb() {
    echo -e "${YELLOW}═══ DynamoDB Table Status ═══${NC}"
    
    for table in image-metadata training-metrics pipeline-state; do
        TABLE_NAME="healthcare-imaging-mlops-${table}"
        
        ITEM_COUNT=$(aws dynamodb describe-table \
            --table-name $TABLE_NAME \
            --query 'Table.ItemCount' \
            --output text 2>/dev/null || echo "N/A")
        
        TABLE_STATUS=$(aws dynamodb describe-table \
            --table-name $TABLE_NAME \
            --query 'Table.TableStatus' \
            --output text 2>/dev/null || echo "N/A")
        
        if [ "$TABLE_STATUS" == "ACTIVE" ]; then
            STATUS="${GREEN}●${NC}"
        else
            STATUS="${RED}●${NC}"
        fi
        
        printf "  %b %-30s Status: %-10s Items: %s\n" "$STATUS" "$table" "$TABLE_STATUS" "$ITEM_COUNT"
    done
    
    echo ""
}

# Monitor S3 Bucket Sizes
monitor_s3() {
    echo -e "${YELLOW}═══ S3 Bucket Storage ═══${NC}"
    
    for bucket_key in training_data_bucket preprocessed_bucket model_artifacts_bucket; do
        BUCKET=$(echo $OUTPUTS | jq -r ".${bucket_key}.value // empty")
        
        if [ -n "$BUCKET" ]; then
            SIZE=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/S3 \
                --metric-name BucketSizeBytes \
                --dimensions Name=BucketName,Value=$BUCKET Name=StorageType,Value=StandardStorage \
                --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[0].Average' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$SIZE" == "None" ] || [ -z "$SIZE" ]; then
                SIZE_MB="0"
            else
                SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
            fi
            
            printf "  %-40s %s MB\n" "$BUCKET" "$SIZE_MB"
        fi
    done
    
    echo ""
}

# Monitor HealthImaging Datastore
monitor_healthimaging() {
    echo -e "${YELLOW}═══ HealthImaging Datastore ═══${NC}"
    
    DATASTORE_ID=$(echo $OUTPUTS | jq -r '.healthimaging_datastore_id.value // empty')
    
    if [ -n "$DATASTORE_ID" ]; then
        DATASTORE_INFO=$(aws medical-imaging get-datastore --datastore-id $DATASTORE_ID 2>/dev/null)
        
        STATUS=$(echo $DATASTORE_INFO | jq -r '.datastoreProperties.datastoreStatus')
        NAME=$(echo $DATASTORE_INFO | jq -r '.datastoreProperties.datastoreName')
        
        if [ "$STATUS" == "ACTIVE" ]; then
            STATUS_ICON="${GREEN}●${NC}"
        else
            STATUS_ICON="${RED}●${NC}"
        fi
        
        printf "  %b Datastore: %-30s Status: %s\n" "$STATUS_ICON" "$NAME" "$STATUS"
    else
        echo "  HealthImaging datastore not configured"
    fi
    
    echo ""
}

# Monitor Recent Alarms
monitor_alarms() {
    echo -e "${YELLOW}═══ CloudWatch Alarms ═══${NC}"
    
    ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "healthcare-imaging-mlops" \
        --query 'MetricAlarms[*].[AlarmName,StateValue]' \
        --output text 2>/dev/null)
    
    if [ -n "$ALARMS" ]; then
        while IFS=$'\t' read -r name state; do
            if [ "$state" == "OK" ]; then
                STATUS="${GREEN}●${NC}"
            elif [ "$state" == "ALARM" ]; then
                STATUS="${RED}●${NC}"
            else
                STATUS="${YELLOW}●${NC}"
            fi
            printf "  %b %-50s %s\n" "$STATUS" "$name" "$state"
        done <<< "$ALARMS"
    else
        echo "  No alarms configured"
    fi
    
    echo ""
}

# Main monitoring loop
main() {
    load_config
    
    while true; do
        show_header
        monitor_pipelines
        monitor_lambda
        monitor_dynamodb
        monitor_s3
        monitor_healthimaging
        monitor_alarms
        
        echo -e "${BLUE}Press Ctrl+C to exit. Refreshing in 30 seconds...${NC}"
        sleep 30
    done
}

# Handle interrupt
trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

main "$@"
