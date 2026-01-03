"""
Healthcare Imaging MLOps Platform - Evaluation Module
Model evaluation and metrics computation
"""

import os
import json
import logging
from typing import Dict, List, Tuple, Optional
import numpy as np

logger = logging.getLogger(__name__)


def load_model(model_path: str) -> "tf.keras.Model":
    """
    Load a trained model.
    
    Args:
        model_path: Path to the saved model
        
    Returns:
        Loaded Keras model
    """
    import tensorflow as tf
    
    logger.info(f"Loading model from {model_path}")
    model = tf.keras.models.load_model(model_path)
    return model


def evaluate_model(
    model: "tf.keras.Model",
    test_generator,
) -> Dict[str, float]:
    """
    Evaluate model on test data.
    
    Args:
        model: Trained Keras model
        test_generator: Test data generator
        
    Returns:
        Dictionary of evaluation metrics
    """
    logger.info("Evaluating model...")
    
    results = model.evaluate(test_generator, verbose=1)
    
    metrics = {}
    for name, value in zip(model.metrics_names, results):
        metrics[name] = float(value)
    
    return metrics


def compute_detailed_metrics(
    model: "tf.keras.Model",
    test_generator,
) -> Dict:
    """
    Compute detailed classification metrics.
    
    Args:
        model: Trained Keras model
        test_generator: Test data generator
        
    Returns:
        Dictionary of detailed metrics
    """
    from sklearn.metrics import (
        classification_report,
        confusion_matrix,
        roc_auc_score,
        precision_recall_curve,
        average_precision_score
    )
    
    # Get predictions
    y_pred_proba = model.predict(test_generator, verbose=1)
    y_pred = np.argmax(y_pred_proba, axis=1)
    y_true = test_generator.classes
    
    # Classification report
    class_names = list(test_generator.class_indices.keys())
    report = classification_report(y_true, y_pred, target_names=class_names, output_dict=True)
    
    # Confusion matrix
    cm = confusion_matrix(y_true, y_pred)
    
    # ROC-AUC (for binary classification)
    if len(class_names) == 2:
        roc_auc = roc_auc_score(y_true, y_pred_proba[:, 1])
        avg_precision = average_precision_score(y_true, y_pred_proba[:, 1])
    else:
        roc_auc = roc_auc_score(y_true, y_pred_proba, multi_class='ovr')
        avg_precision = None
    
    # Compute per-class metrics
    per_class_metrics = {}
    for class_name in class_names:
        per_class_metrics[class_name] = {
            "precision": report[class_name]["precision"],
            "recall": report[class_name]["recall"],
            "f1-score": report[class_name]["f1-score"],
            "support": report[class_name]["support"]
        }
    
    detailed_metrics = {
        "accuracy": report["accuracy"],
        "macro_avg": report["macro avg"],
        "weighted_avg": report["weighted avg"],
        "per_class": per_class_metrics,
        "confusion_matrix": cm.tolist(),
        "roc_auc": roc_auc,
        "average_precision": avg_precision
    }
    
    return detailed_metrics


def check_model_quality(
    metrics: Dict,
    accuracy_threshold: float = 0.85,
    precision_threshold: float = 0.80,
    recall_threshold: float = 0.80
) -> Tuple[bool, str]:
    """
    Check if model meets quality thresholds.
    
    Args:
        metrics: Dictionary of evaluation metrics
        accuracy_threshold: Minimum accuracy required
        precision_threshold: Minimum precision required
        recall_threshold: Minimum recall required
        
    Returns:
        Tuple of (passed, message)
    """
    accuracy = metrics.get("accuracy", 0)
    precision = metrics.get("weighted_avg", {}).get("precision", 0)
    recall = metrics.get("weighted_avg", {}).get("recall", 0)
    
    checks = []
    passed = True
    
    if accuracy < accuracy_threshold:
        checks.append(f"Accuracy {accuracy:.4f} < {accuracy_threshold}")
        passed = False
    else:
        checks.append(f"Accuracy {accuracy:.4f} >= {accuracy_threshold} ✓")
    
    if precision < precision_threshold:
        checks.append(f"Precision {precision:.4f} < {precision_threshold}")
        passed = False
    else:
        checks.append(f"Precision {precision:.4f} >= {precision_threshold} ✓")
    
    if recall < recall_threshold:
        checks.append(f"Recall {recall:.4f} < {recall_threshold}")
        passed = False
    else:
        checks.append(f"Recall {recall:.4f} >= {recall_threshold} ✓")
    
    message = "\n".join(checks)
    
    return passed, message


def save_evaluation_report(
    metrics: Dict,
    output_path: str,
    model_version: str = "1.0.0"
) -> str:
    """
    Save evaluation report to JSON file.
    
    Args:
        metrics: Dictionary of evaluation metrics
        output_path: Output file path
        model_version: Model version string
        
    Returns:
        Path to saved report
    """
    import datetime
    
    report = {
        "model_version": model_version,
        "evaluation_timestamp": datetime.datetime.utcnow().isoformat(),
        "metrics": metrics
    }
    
    with open(output_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    logger.info(f"Evaluation report saved to {output_path}")
    
    return output_path


def create_evaluation_artifacts(
    model: "tf.keras.Model",
    test_generator,
    output_dir: str
) -> Dict[str, str]:
    """
    Create all evaluation artifacts.
    
    Args:
        model: Trained Keras model
        test_generator: Test data generator
        output_dir: Output directory
        
    Returns:
        Dictionary of artifact paths
    """
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from sklearn.metrics import roc_curve, precision_recall_curve
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Get predictions
    y_pred_proba = model.predict(test_generator, verbose=1)
    y_true = test_generator.classes
    
    artifacts = {}
    
    # ROC Curve
    if y_pred_proba.shape[1] == 2:
        fpr, tpr, _ = roc_curve(y_true, y_pred_proba[:, 1])
        
        plt.figure(figsize=(8, 6))
        plt.plot(fpr, tpr, 'b-', label='ROC Curve')
        plt.plot([0, 1], [0, 1], 'r--', label='Random')
        plt.xlabel('False Positive Rate')
        plt.ylabel('True Positive Rate')
        plt.title('ROC Curve')
        plt.legend()
        plt.grid(True)
        
        roc_path = os.path.join(output_dir, 'roc_curve.png')
        plt.savefig(roc_path, dpi=150, bbox_inches='tight')
        plt.close()
        artifacts['roc_curve'] = roc_path
        
        # Precision-Recall Curve
        precision, recall, _ = precision_recall_curve(y_true, y_pred_proba[:, 1])
        
        plt.figure(figsize=(8, 6))
        plt.plot(recall, precision, 'b-', label='PR Curve')
        plt.xlabel('Recall')
        plt.ylabel('Precision')
        plt.title('Precision-Recall Curve')
        plt.legend()
        plt.grid(True)
        
        pr_path = os.path.join(output_dir, 'pr_curve.png')
        plt.savefig(pr_path, dpi=150, bbox_inches='tight')
        plt.close()
        artifacts['pr_curve'] = pr_path
    
    # Confusion Matrix
    from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay
    
    y_pred = np.argmax(y_pred_proba, axis=1)
    cm = confusion_matrix(y_true, y_pred)
    
    plt.figure(figsize=(8, 6))
    disp = ConfusionMatrixDisplay(cm, display_labels=list(test_generator.class_indices.keys()))
    disp.plot(cmap='Blues')
    plt.title('Confusion Matrix')
    
    cm_path = os.path.join(output_dir, 'confusion_matrix.png')
    plt.savefig(cm_path, dpi=150, bbox_inches='tight')
    plt.close()
    artifacts['confusion_matrix'] = cm_path
    
    return artifacts


if __name__ == "__main__":
    # Entry point for SageMaker Processing Job
    import argparse
    import tensorflow as tf
    from tensorflow.keras.preprocessing.image import ImageDataGenerator
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=str, default="/opt/ml/processing/model")
    parser.add_argument("--test-dir", type=str, default="/opt/ml/processing/test")
    parser.add_argument("--output-dir", type=str, default="/opt/ml/processing/evaluation")
    parser.add_argument("--accuracy-threshold", type=float, default=0.85)
    parser.add_argument("--target-size", type=int, default=512)
    args = parser.parse_args()
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Load model
    print("Loading model...")
    model = load_model(args.model_dir)
    
    # Create test generator
    print("Creating test generator...")
    test_datagen = ImageDataGenerator(rescale=1./255)
    test_generator = test_datagen.flow_from_directory(
        args.test_dir,
        target_size=(args.target_size, args.target_size),
        batch_size=32,
        class_mode='categorical',
        color_mode='grayscale',
        shuffle=False
    )
    
    # Evaluate model
    print("Evaluating model...")
    basic_metrics = evaluate_model(model, test_generator)
    detailed_metrics = compute_detailed_metrics(model, test_generator)
    
    # Check quality
    passed, message = check_model_quality(
        detailed_metrics,
        accuracy_threshold=args.accuracy_threshold
    )
    
    print(f"\nQuality Check Results:\n{message}")
    print(f"\nModel {'PASSED' if passed else 'FAILED'} quality checks")
    
    # Save evaluation report
    all_metrics = {**basic_metrics, **detailed_metrics, "quality_check_passed": passed}
    save_evaluation_report(all_metrics, os.path.join(args.output_dir, 'evaluation_report.json'))
    
    # Create evaluation artifacts
    print("Creating evaluation artifacts...")
    artifacts = create_evaluation_artifacts(model, test_generator, args.output_dir)
    
    print(f"\nEvaluation complete. Results saved to {args.output_dir}")
