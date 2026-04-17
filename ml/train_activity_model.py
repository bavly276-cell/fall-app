from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import tensorflow as tf

SEED = 43
np.random.seed(SEED)
tf.random.set_seed(SEED)

ROOT = Path(__file__).resolve().parents[1]
MODEL_OUT = ROOT / "assets" / "models" / "activity_classifier.tflite"
METRICS_OUT = ROOT / "ml" / "output" / "activity_metrics.json"
WINDOW = 60
FEATURES = 2
CLASSES = ["walking", "running", "sitting", "sleeping"]


def synth_activity_dataset(n_each: int = 900) -> tuple[np.ndarray, np.ndarray]:
    x_list = []
    y_list = []

    for _ in range(n_each):
        accel = np.abs(np.random.normal(0.18, 0.06, WINDOW))
        gyro = np.abs(np.random.normal(0.22, 0.08, WINDOW))
        x_list.append(np.stack([np.clip(accel, 0, 1), np.clip(gyro, 0, 1)], axis=1))
        y_list.append(0)

    for _ in range(n_each):
        accel = np.abs(np.random.normal(0.55, 0.16, WINDOW))
        gyro = np.abs(np.random.normal(0.7, 0.2, WINDOW))
        x_list.append(np.stack([np.clip(accel, 0, 1), np.clip(gyro, 0, 1)], axis=1))
        y_list.append(1)

    for _ in range(n_each):
        accel = np.abs(np.random.normal(0.04, 0.02, WINDOW))
        gyro = np.abs(np.random.normal(0.05, 0.02, WINDOW))
        x_list.append(np.stack([np.clip(accel, 0, 1), np.clip(gyro, 0, 1)], axis=1))
        y_list.append(2)

    for _ in range(n_each):
        accel = np.abs(np.random.normal(0.02, 0.01, WINDOW))
        gyro = np.abs(np.random.normal(0.03, 0.01, WINDOW))
        x_list.append(np.stack([np.clip(accel, 0, 1), np.clip(gyro, 0, 1)], axis=1))
        y_list.append(3)

    x = np.array(x_list, dtype=np.float32)
    y = np.array(y_list, dtype=np.int32)
    order = np.arange(len(x))
    np.random.shuffle(order)
    return x[order], y[order]


def build_model() -> tf.keras.Model:
    model = tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(WINDOW, FEATURES)),
            tf.keras.layers.Conv1D(24, 5, activation="relu"),
            tf.keras.layers.Conv1D(32, 3, activation="relu"),
            tf.keras.layers.GlobalAveragePooling1D(),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dense(len(CLASSES), activation="softmax"),
        ]
    )
    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def main() -> None:
    x, y = synth_activity_dataset()
    split = int(len(x) * 0.8)
    x_train, x_val = x[:split], x[split:]
    y_train, y_val = y[:split], y[split:]

    model = build_model()
    model.fit(
        x_train,
        y_train,
        validation_data=(x_val, y_val),
        epochs=20,
        batch_size=64,
        verbose=2,
    )

    val_loss, val_acc = model.evaluate(x_val, y_val, verbose=0)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    MODEL_OUT.write_bytes(tflite_model)

    METRICS_OUT.parent.mkdir(parents=True, exist_ok=True)
    metrics = {
        "val_loss": float(val_loss),
        "val_accuracy": float(val_acc),
        "classes": CLASSES,
        "window": WINDOW,
        "features": FEATURES,
        "model": str(MODEL_OUT.relative_to(ROOT)),
    }
    METRICS_OUT.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(f"Saved {MODEL_OUT}")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
