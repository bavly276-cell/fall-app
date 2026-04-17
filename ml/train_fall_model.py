from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf

SEED = 42
np.random.seed(SEED)
tf.random.set_seed(SEED)

ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "ml" / "data" / "fall_timeseries.csv"
MODEL_OUT = ROOT / "assets" / "models" / "fall_detector.tflite"
METRICS_OUT = ROOT / "ml" / "output" / "fall_metrics.json"
WINDOW = 60
FEATURES = 2


def _synthetic_dataset(n_samples: int = 4000) -> tuple[np.ndarray, np.ndarray]:
    normal = int(n_samples * 0.7)
    falls = n_samples - normal

    x = np.zeros((n_samples, WINDOW, FEATURES), dtype=np.float32)
    y = np.zeros((n_samples,), dtype=np.float32)

    for i in range(normal):
        accel = 1.0 + np.random.normal(0, 0.06, WINDOW)
        gyro = np.abs(np.random.normal(0.08, 0.05, WINDOW))
        x[i, :, 0] = np.clip(np.abs(accel - 1.0), 0, 4) / 4.0
        x[i, :, 1] = np.clip(gyro, 0, 8) / 8.0

    for i in range(falls):
        idx = normal + i
        accel = 1.0 + np.random.normal(0, 0.08, WINDOW)
        gyro = np.abs(np.random.normal(0.12, 0.07, WINDOW))

        ff_start = np.random.randint(8, 20)
        impact_idx = ff_start + np.random.randint(8, 14)

        accel[ff_start:impact_idx] = np.random.uniform(0.15, 0.5, impact_idx - ff_start)
        accel[impact_idx] = np.random.uniform(2.9, 4.2)
        end = min(WINDOW, impact_idx + 8)
        accel[impact_idx + 1 : end] = np.random.uniform(1.3, 2.1, max(0, end - (impact_idx + 1)))

        gyro[impact_idx : min(WINDOW, impact_idx + 6)] = np.random.uniform(1.4, 4.5, min(WINDOW, impact_idx + 6) - impact_idx)

        x[idx, :, 0] = np.clip(np.abs(accel - 1.0), 0, 4) / 4.0
        x[idx, :, 1] = np.clip(gyro, 0, 8) / 8.0
        y[idx] = 1.0

    order = np.arange(n_samples)
    np.random.shuffle(order)
    return x[order], y[order]


def _load_dataset_from_csv(path: Path) -> tuple[np.ndarray, np.ndarray]:
    df = pd.read_csv(path)
    required = {"accel_mag", "gyro_mag", "label"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns in CSV: {sorted(missing)}")

    accel = df["accel_mag"].astype(float).to_numpy()
    gyro = df["gyro_mag"].astype(float).to_numpy()
    labels = df["label"].astype(int).to_numpy()

    x_list: list[np.ndarray] = []
    y_list: list[int] = []

    for start in range(0, len(df) - WINDOW + 1, 6):
        end = start + WINDOW
        window_acc = accel[start:end]
        window_gyro = gyro[start:end]
        window_label = labels[start:end]

        xw = np.stack(
            [
                np.clip(np.abs(window_acc - 1.0), 0, 4) / 4.0,
                np.clip(np.abs(window_gyro), 0, 8) / 8.0,
            ],
            axis=1,
        )

        yv = int(np.mean(window_label) >= 0.5)
        x_list.append(xw.astype(np.float32))
        y_list.append(yv)

    if not x_list:
        raise ValueError("CSV did not produce any windows")

    return np.stack(x_list), np.array(y_list, dtype=np.float32)


def build_model() -> tf.keras.Model:
    model = tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(WINDOW, FEATURES)),
            tf.keras.layers.Conv1D(32, 5, activation="relu"),
            tf.keras.layers.Conv1D(64, 3, activation="relu"),
            tf.keras.layers.GlobalAveragePooling1D(),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dropout(0.2),
            tf.keras.layers.Dense(1, activation="sigmoid"),
        ]
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="binary_crossentropy",
        metrics=["accuracy", tf.keras.metrics.Precision(), tf.keras.metrics.Recall()],
    )
    return model


def main() -> None:
    if DATA_PATH.exists():
        x, y = _load_dataset_from_csv(DATA_PATH)
        print(f"Loaded dataset from {DATA_PATH} with shape {x.shape}")
    else:
        x, y = _synthetic_dataset()
        print("Using synthetic dataset (ml/data/fall_timeseries.csv not found)")

    split = int(len(x) * 0.8)
    x_train, x_val = x[:split], x[split:]
    y_train, y_val = y[:split], y[split:]

    model = build_model()
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=5,
            restore_best_weights=True,
        )
    ]

    model.fit(
        x_train,
        y_train,
        validation_data=(x_val, y_val),
        epochs=30,
        batch_size=64,
        callbacks=callbacks,
        verbose=2,
    )

    val_loss, val_acc, val_precision, val_recall = model.evaluate(x_val, y_val, verbose=0)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    MODEL_OUT.write_bytes(tflite_model)

    METRICS_OUT.parent.mkdir(parents=True, exist_ok=True)
    metrics = {
        "val_loss": float(val_loss),
        "val_accuracy": float(val_acc),
        "val_precision": float(val_precision),
        "val_recall": float(val_recall),
        "window": WINDOW,
        "features": FEATURES,
        "model": str(MODEL_OUT.relative_to(ROOT)),
    }
    METRICS_OUT.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print("Saved:")
    print(f"- {MODEL_OUT}")
    print(f"- {METRICS_OUT}")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
