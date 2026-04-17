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
META_OUT = ROOT / "assets" / "models" / "fall_detector_meta.json"
METRICS_OUT = ROOT / "ml" / "output" / "fall_metrics.json"
SAMPLE_HZ = 25
WINDOW_SECONDS = 2.5
WINDOW = int(SAMPLE_HZ * WINDOW_SECONDS)
TRAIN_STRIDE = 5
LABEL_POSITIVE_RATIO = 0.3
FEATURE_COLUMNS = [
    ("acc_x", ["acc_x", "ax", "accx"]),
    ("acc_y", ["acc_y", "ay", "accy"]),
    ("acc_z", ["acc_z", "az", "accz"]),
    ("gyro_x", ["gyro_x", "gx", "gyrox"]),
    ("gyro_y", ["gyro_y", "gy", "gyroy"]),
    ("gyro_z", ["gyro_z", "gz", "gyroz"]),
]
FEATURES = len(FEATURE_COLUMNS)


def _resolve_column(df: pd.DataFrame, aliases: list[str]) -> str:
    lower = {c.lower(): c for c in df.columns}
    for key in aliases:
        hit = lower.get(key.lower())
        if hit is not None:
            return hit
    raise KeyError(f"None of aliases exist in CSV: {aliases}")


def _synthetic_dataset(n_windows: int = 5000) -> tuple[np.ndarray, np.ndarray]:
    x = np.zeros((n_windows, WINDOW, FEATURES), dtype=np.float32)
    y = np.zeros((n_windows,), dtype=np.float32)

    normal = int(n_windows * 0.7)
    for i in range(normal):
        ax = np.random.normal(0.02, 0.18, WINDOW)
        ay = np.random.normal(0.01, 0.18, WINDOW)
        az = np.random.normal(1.0, 0.22, WINDOW)
        gx = np.random.normal(0.0, 18.0, WINDOW)
        gy = np.random.normal(0.0, 18.0, WINDOW)
        gz = np.random.normal(0.0, 18.0, WINDOW)
        x[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1).astype(np.float32)

    falls = n_windows - normal
    for i in range(falls):
        idx = normal + i
        ax = np.random.normal(0.02, 0.2, WINDOW)
        ay = np.random.normal(0.02, 0.2, WINDOW)
        az = np.random.normal(1.0, 0.25, WINDOW)
        gx = np.random.normal(0.0, 20.0, WINDOW)
        gy = np.random.normal(0.0, 20.0, WINDOW)
        gz = np.random.normal(0.0, 20.0, WINDOW)

        ff_start = np.random.randint(6, 16)
        impact_idx = ff_start + np.random.randint(10, 18)
        impact_idx = min(impact_idx, WINDOW - 2)

        az[ff_start:impact_idx] = np.random.uniform(0.1, 0.5, impact_idx - ff_start)
        ax[impact_idx] += np.random.uniform(2.0, 3.8)
        ay[impact_idx] += np.random.uniform(1.5, 3.4)
        az[impact_idx] += np.random.uniform(2.5, 4.5)

        span_end = min(WINDOW, impact_idx + 8)
        gx[impact_idx:span_end] += np.random.uniform(170.0, 360.0, span_end - impact_idx)
        gy[impact_idx:span_end] += np.random.uniform(120.0, 320.0, span_end - impact_idx)
        gz[impact_idx:span_end] += np.random.uniform(120.0, 320.0, span_end - impact_idx)

        x[idx] = np.stack([ax, ay, az, gx, gy, gz], axis=1).astype(np.float32)
        y[idx] = 1.0

    order = np.arange(n_windows)
    np.random.shuffle(order)
    return x[order], y[order]


def _load_dataset_from_csv(path: Path) -> tuple[np.ndarray, np.ndarray]:
    df = pd.read_csv(path)

    resolved = []
    for _, aliases in FEATURE_COLUMNS:
        resolved.append(_resolve_column(df, aliases))
    label_col = _resolve_column(df, ["label", "fall", "target"])

    feature_data = df[resolved].astype(float).to_numpy()
    labels = df[label_col].astype(int).to_numpy()

    x_list: list[np.ndarray] = []
    y_list: list[int] = []

    for start in range(0, len(feature_data) - WINDOW + 1, TRAIN_STRIDE):
        end = start + WINDOW
        window_x = feature_data[start:end]
        window_y = labels[start:end]

        label = int(np.mean(window_y) >= LABEL_POSITIVE_RATIO)
        x_list.append(window_x.astype(np.float32))
        y_list.append(label)

    if not x_list:
        raise ValueError(
            f"Dataset too small for WINDOW={WINDOW}. Need at least {WINDOW} rows."
        )

    return np.stack(x_list), np.array(y_list, dtype=np.float32)


def _train_val_split(
    x: np.ndarray,
    y: np.ndarray,
    train_ratio: float = 0.8,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    idx = np.arange(len(x))
    np.random.shuffle(idx)
    x, y = x[idx], y[idx]

    split = int(len(x) * train_ratio)
    split = min(max(split, 1), len(x) - 1)
    return x[:split], x[split:], y[:split], y[split:]


def _fit_normalization(train_x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mean = train_x.reshape(-1, FEATURES).mean(axis=0)
    std = train_x.reshape(-1, FEATURES).std(axis=0)
    std = np.where(std < 1e-6, 1.0, std)
    return mean.astype(np.float32), std.astype(np.float32)


def _apply_normalization(x: np.ndarray, mean: np.ndarray, std: np.ndarray) -> np.ndarray:
    return ((x - mean[None, None, :]) / std[None, None, :]).astype(np.float32)


def build_model() -> tf.keras.Model:
    model = tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(WINDOW, FEATURES)),
            tf.keras.layers.SeparableConv1D(24, 5, activation="relu", padding="same"),
            tf.keras.layers.SeparableConv1D(24, 5, activation="relu", padding="same"),
            tf.keras.layers.MaxPool1D(pool_size=2),
            tf.keras.layers.SeparableConv1D(32, 3, activation="relu", padding="same"),
            tf.keras.layers.GlobalAveragePooling1D(),
            tf.keras.layers.Dense(24, activation="relu"),
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


def _f1_at_threshold(y_true: np.ndarray, y_prob: np.ndarray, threshold: float) -> tuple[float, float, float]:
    y_hat = (y_prob >= threshold).astype(np.int32)
    y_t = y_true.astype(np.int32)

    tp = int(np.sum((y_t == 1) & (y_hat == 1)))
    fp = int(np.sum((y_t == 0) & (y_hat == 1)))
    fn = int(np.sum((y_t == 1) & (y_hat == 0)))

    precision = tp / max(tp + fp, 1)
    recall = tp / max(tp + fn, 1)
    f1 = (2 * precision * recall) / max(precision + recall, 1e-9)
    return f1, precision, recall


def _find_best_threshold(y_true: np.ndarray, y_prob: np.ndarray) -> tuple[float, float, float, float]:
    best_t = 0.5
    best_f1 = -1.0
    best_p = 0.0
    best_r = 0.0

    for t in np.linspace(0.25, 0.9, 66):
        f1, p, r = _f1_at_threshold(y_true, y_prob, float(t))
        if f1 > best_f1:
            best_f1 = f1
            best_t = float(t)
            best_p = p
            best_r = r

    return best_t, best_f1, best_p, best_r


def main() -> None:
    if DATA_PATH.exists():
        x, y = _load_dataset_from_csv(DATA_PATH)
        print(f"Loaded dataset from {DATA_PATH} with shape {x.shape}")
    else:
        x, y = _synthetic_dataset()
        print("Using synthetic dataset (ml/data/fall_timeseries.csv not found)")

    x_train, x_val, y_train, y_val = _train_val_split(x, y, train_ratio=0.8)

    mean, std = _fit_normalization(x_train)
    x_train = _apply_normalization(x_train, mean, std)
    x_val = _apply_normalization(x_val, mean, std)

    print(f"Train windows: {len(x_train)} | Val windows: {len(x_val)}")
    print(f"Fall ratio train={y_train.mean():.3f} val={y_val.mean():.3f}")

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
        epochs=35,
        batch_size=64,
        callbacks=callbacks,
        verbose=2,
    )

    val_loss, val_acc, _, _ = model.evaluate(x_val, y_val, verbose=0)
    val_prob = model.predict(x_val, verbose=0).reshape(-1)
    best_t, best_f1, best_precision, best_recall = _find_best_threshold(y_val, val_prob)

    # Dynamic-range quantization for small model and fast CPU inference.
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    MODEL_OUT.write_bytes(tflite_model)

    metadata = {
        "feature_order": [name for name, _ in FEATURE_COLUMNS],
        "window_size": WINDOW,
        "sample_hz": SAMPLE_HZ,
        "inference_interval_ms": 240,
        "threshold": best_t,
        "mean": [float(v) for v in mean.tolist()],
        "std": [float(v) for v in std.tolist()],
    }
    META_OUT.parent.mkdir(parents=True, exist_ok=True)
    META_OUT.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    METRICS_OUT.parent.mkdir(parents=True, exist_ok=True)
    metrics = {
        "val_loss": float(val_loss),
        "val_accuracy": float(val_acc),
        "best_threshold": float(best_t),
        "val_precision": float(best_precision),
        "val_recall": float(best_recall),
        "val_f1": float(best_f1),
        "window": WINDOW,
        "features": FEATURES,
        "sample_hz": SAMPLE_HZ,
        "model": str(MODEL_OUT.relative_to(ROOT)),
        "metadata": str(META_OUT.relative_to(ROOT)),
    }
    METRICS_OUT.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print("Saved:")
    print(f"- {MODEL_OUT}")
    print(f"- {META_OUT}")
    print(f"- {METRICS_OUT}")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
