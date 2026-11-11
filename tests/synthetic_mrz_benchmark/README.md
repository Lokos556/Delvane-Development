# Synthetic MRZ OCR strategy comparison

- Cases: 18
- Baseline exact reads: 0/18; mean CER 10.3%
- MRZ-tuned exact reads: 0/18; mean CER 8.4%

> Synthetic text strips only. These figures are not a real-document accuracy claim and do not measure browser OCR or full-card detection.

| Format | Scenario | Baseline exact | Tuned exact | Baseline CER | Tuned CER |
|---|---|---:|---:|---:|---:|
| TD1 | blur | no | no | 2.2% | 2.2% |
| TD1 | clean | no | no | 3.3% | 2.2% |
| TD1 | glare | no | no | 8.9% | 8.9% |
| TD1 | low_contrast | no | no | 3.3% | 2.2% |
| TD1 | skew | no | no | 12.2% | 12.2% |
| TD1 | small | no | no | 17.8% | 12.2% |
| TD2 | blur | no | no | 1.4% | 1.4% |
| TD2 | clean | no | no | 1.4% | 1.4% |
| TD2 | glare | no | no | 23.6% | 22.2% |
| TD2 | low_contrast | no | no | 1.4% | 1.4% |
| TD2 | skew | no | no | 11.1% | 9.7% |
| TD2 | small | no | no | 9.7% | 4.2% |
| TD3 | blur | no | no | 3.4% | 1.1% |
| TD3 | clean | no | no | 2.3% | 1.1% |
| TD3 | glare | no | no | 38.6% | 39.8% |
| TD3 | low_contrast | no | no | 1.1% | 1.1% |
| TD3 | skew | no | no | 26.1% | 21.6% |
| TD3 | small | no | no | 18.2% | 5.7% |
