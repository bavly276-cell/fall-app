Place TensorFlow Lite models in this directory.

Required files for this project:
- fall_detector.tflite
- fall_detector_meta.json
- activity_classifier.tflite (optional)

Generate with:
- python ml/train_fall_model.py
- python ml/train_activity_model.py

`fall_detector.tflite` expects a 6-axis window:
- [acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z]
