# ============================================================================
# NETWORKING MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "sagemaker_security_group_id" {
  description = "ID of the SageMaker security group"
  value       = aws_security_group.sagemaker.id
}

output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = var.enable_nat_gateway ? aws_nat_gateway.main[0].id : null
}
