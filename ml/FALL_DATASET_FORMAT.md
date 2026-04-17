# Fall Dataset Format (6-Axis Time Series)

Use one sensor sample per row.

Required columns:
- timestamp_ms
- acc_x, acc_y, acc_z
- gyro_x, gyro_y, gyro_z
- label

Where:
- `label = 1` for fall sample
- `label = 0` for normal activity sample

Example CSV:

```csv
timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z,label
1710000000000,0.01,-0.03,0.98,2.1,-1.2,0.8,0
1710000000040,0.02,-0.02,1.01,1.7,-0.9,0.5,0
1710000000080,0.03,-0.02,0.99,2.3,-1.1,0.4,0
1710000000120,0.06,0.11,0.42,28.2,34.1,22.0,1
1710000000160,1.90,2.35,3.84,240.0,198.0,221.0,1
```

Sampling guidance:
- 25-50 Hz recommended
- Keep timeline continuous per recording session
- Include many ADL activities in normal class: walking, running, sitting, lying, stairs

Window labeling used in training script:
- Window length: 2.5s (default)
- Sliding stride: 5 samples (default)
- Window label is Fall if at least 30% of samples in window have label=1

This allows robust detection of short impact segments without requiring every sample in the window to be labeled as fall.
