"""
Healthcare Imaging MLOps Platform - Training Module
ResNet-50 based pneumonia detection model training
"""

import os
import json
import logging
from typing import Dict, List, Tuple, Optional
import numpy as np

logger = logging.getLogger(__name__)


def create_model(
    input_shape: Tuple[int, int, int] = (512, 512, 1),
    num_classes: int = 2,
    pretrained: bool = True
) -> "tf.keras.Model":
    """
    Create a ResNet-50 based model for pneumonia detection.
    
    Args:
        input_shape: Input image shape (height, width, channels)
        num_classes: Number of output classes
        pretrained: Whether to use ImageNet pretrained weights
        
    Returns:
        Keras model
    """
    import tensorflow as tf
    from tensorflow.keras import layers, models
    from tensorflow.keras.applications import ResNet50
    
    # Handle single channel input by repeating to 3 channels
    inputs = layers.Input(shape=input_shape)
    
    if input_shape[-1] == 1:
        x = layers.Concatenate()([inputs, inputs, inputs])
    else:
        x = inputs
    
    # Resize to ResNet expected input size
    x = layers.Resizing(224, 224)(x)
    
    # Load pretrained ResNet50
    base_model = ResNet50(
        weights='imagenet' if pretrained else None,
        include_top=False,
        input_tensor=x
    )
    
    # Freeze base model layers for transfer learning
    if pretrained:
        for layer in base_model.layers[:-20]:
            layer.trainable = False
    
    # Add classification head
    x = base_model.output
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(512, activation='relu')(x)
    x = layers.Dropout(0.5)(x)
    x = layers.Dense(256, activation='relu')(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(num_classes, activation='softmax')(x)
    
    model = models.Model(inputs=inputs, outputs=outputs)
    
    return model


def compile_model(
    model: "tf.keras.Model",
    learning_rate: float = 1e-4,
    optimizer: str = "adam"
) -> "tf.keras.Model":
    """
    Compile the model with optimizer and loss function.
    
    Args:
        model: Keras model
        learning_rate: Learning rate for optimizer
        optimizer: Optimizer name
        
    Returns:
        Compiled model
    """
    import tensorflow as tf
    
    if optimizer.lower() == "adam":
        opt = tf.keras.optimizers.Adam(learning_rate=learning_rate)
    elif optimizer.lower() == "sgd":
        opt = tf.keras.optimizers.SGD(learning_rate=learning_rate, momentum=0.9)
    else:
        opt = tf.keras.optimizers.Adam(learning_rate=learning_rate)
    
    model.compile(
        optimizer=opt,
        loss='categorical_crossentropy',
        metrics=[
            'accuracy',
            tf.keras.metrics.Precision(name='precision'),
            tf.keras.metrics.Recall(name='recall'),
            tf.keras.metrics.AUC(name='auc')
        ]
    )
    
    return model


def create_data_generator(
    data_dir: str,
    batch_size: int = 32,
    target_size: Tuple[int, int] = (512, 512),
    augment: bool = False
) -> "tf.keras.preprocessing.image.ImageDataGenerator":
    """
    Create a data generator for training.
    
    Args:
        data_dir: Directory containing image data
        batch_size: Batch size
        target_size: Target image size
        augment: Whether to apply data augmentation
        
    Returns:
        Data generator
    """
    from tensorflow.keras.preprocessing.image import ImageDataGenerator
    
    if augment:
        datagen = ImageDataGenerator(
            rescale=1./255,
            rotation_range=15,
            width_shift_range=0.1,
            height_shift_range=0.1,
            horizontal_flip=True,
            zoom_range=0.1,
            fill_mode='constant',
            cval=0
        )
    else:
        datagen = ImageDataGenerator(rescale=1./255)
    
    generator = datagen.flow_from_directory(
        data_dir,
        target_size=target_size,
        batch_size=batch_size,
        class_mode='categorical',
        color_mode='grayscale',
        shuffle=True
    )
    
    return generator


def create_callbacks(
    model_dir: str,
    patience: int = 10,
    min_delta: float = 0.001
) -> List:
    """
    Create training callbacks.
    
    Args:
        model_dir: Directory to save model checkpoints
        patience: Early stopping patience
        min_delta: Minimum improvement for early stopping
        
    Returns:
        List of callbacks
    """
    import tensorflow as tf
    
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=patience,
            min_delta=min_delta,
            restore_best_weights=True,
            verbose=1
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=os.path.join(model_dir, 'best_model.h5'),
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-7,
            verbose=1
        ),
        tf.keras.callbacks.TensorBoard(
            log_dir=os.path.join(model_dir, 'logs'),
            histogram_freq=1
        )
    ]
    
    return callbacks


def train_model(
    model: "tf.keras.Model",
    train_generator,
    val_generator,
    epochs: int = 50,
    callbacks: List = None
) -> Dict:
    """
    Train the model.
    
    Args:
        model: Compiled Keras model
        train_generator: Training data generator
        val_generator: Validation data generator
        epochs: Number of training epochs
        callbacks: List of callbacks
        
    Returns:
        Training history
    """
    history = model.fit(
        train_generator,
        validation_data=val_generator,
        epochs=epochs,
        callbacks=callbacks,
        verbose=1
    )
    
    return history.history


def save_model(model: "tf.keras.Model", output_dir: str) -> str:
    """
    Save the trained model.
    
    Args:
        model: Trained Keras model
        output_dir: Output directory
        
    Returns:
        Path to saved model
    """
    import tensorflow as tf
    
    # Save in SavedModel format
    model_path = os.path.join(output_dir, 'model')
    model.save(model_path)
    
    # Also save in H5 format
    h5_path = os.path.join(output_dir, 'model.h5')
    model.save(h5_path)
    
    logger.info(f"Model saved to {model_path}")
    
    return model_path


def save_training_metrics(history: Dict, output_dir: str) -> str:
    """
    Save training metrics to JSON file.
    
    Args:
        history: Training history dictionary
        output_dir: Output directory
        
    Returns:
        Path to metrics file
    """
    metrics_path = os.path.join(output_dir, 'training_metrics.json')
    
    # Convert numpy types to Python types
    metrics = {}
    for key, values in history.items():
        metrics[key] = [float(v) for v in values]
    
    with open(metrics_path, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    logger.info(f"Training metrics saved to {metrics_path}")
    
    return metrics_path


if __name__ == "__main__":
    # Entry point for SageMaker Training Job
    import argparse
    import tensorflow as tf
    
    parser = argparse.ArgumentParser()
    
    # Hyperparameters
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=1e-4)
    parser.add_argument("--target-size", type=int, default=512)
    parser.add_argument("--patience", type=int, default=10)
    
    # SageMaker specific arguments
    parser.add_argument("--model-dir", type=str, default=os.environ.get("SM_MODEL_DIR", "/opt/ml/model"))
    parser.add_argument("--train", type=str, default=os.environ.get("SM_CHANNEL_TRAINING", "/opt/ml/input/data/training"))
    parser.add_argument("--validation", type=str, default=os.environ.get("SM_CHANNEL_VALIDATION", "/opt/ml/input/data/validation"))
    
    args = parser.parse_args()
    
    # Set GPU memory growth
    gpus = tf.config.experimental.list_physical_devices('GPU')
    if gpus:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
    
    # Create model
    print("Creating model...")
    model = create_model(
        input_shape=(args.target_size, args.target_size, 1),
        num_classes=2,
        pretrained=True
    )
    
    # Compile model
    print("Compiling model...")
    model = compile_model(model, learning_rate=args.learning_rate)
    
    # Create data generators
    print("Creating data generators...")
    train_generator = create_data_generator(
        args.train,
        batch_size=args.batch_size,
        target_size=(args.target_size, args.target_size),
        augment=True
    )
    
    val_generator = create_data_generator(
        args.validation,
        batch_size=args.batch_size,
        target_size=(args.target_size, args.target_size),
        augment=False
    )
    
    # Create callbacks
    callbacks = create_callbacks(args.model_dir, patience=args.patience)
    
    # Train model
    print("Starting training...")
    history = train_model(
        model,
        train_generator,
        val_generator,
        epochs=args.epochs,
        callbacks=callbacks
    )
    
    # Save model and metrics
    print("Saving model...")
    save_model(model, args.model_dir)
    save_training_metrics(history, args.model_dir)
    
    print("Training complete!")
