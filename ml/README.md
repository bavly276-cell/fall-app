Model training scripts for on-device inference.

Usage:
1. python -m venv .venv
2. .venv\\Scripts\\activate
3. pip install -r ml/requirements.txt
4. python ml/train_fall_model.py
5. python ml/train_activity_model.py

Outputs:
- assets/models/fall_detector.tflite
- assets/models/activity_classifier.tflite
- ml/output/*.json
