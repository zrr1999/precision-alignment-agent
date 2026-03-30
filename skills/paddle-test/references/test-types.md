# Test Types Reference

## Paddle Unit Tests vs PaddleTest vs PaddleAPITest

| Aspect | Paddle Unit Test | PaddleTest | PaddleAPITest |
|--------|-----------------|------------|---------------|
| **Repo** | Paddle (internal) | PaddleTest (separate repo) | PaddleAPITest (separate repo) |
| **Purpose** | Op-level correctness | API functional coverage | Precision alignment (atol=0, rtol=0) |
| **Runner** | `python test_file.py` | `pytest test_file.py` | `python engineV2.py --config ...` |
| **Tolerance** | Per-test defined | Per-test defined | Strict: atol=0, rtol=0 |
| **Skill** | `paddle-test` | `paddle-test` | `precision-validation` |
| **Used by** | Builder, Reviewer | Builder, Reviewer | Validator only |
| **Path param** | `PADDLE_PATH` | `PADDLETEST_PATH` | `PADDLEAPITEST_PATH` |

## Common Mistakes

1. **Passing PaddleTest path to Validator** — Validator needs `PADDLEAPITEST_PATH`, not `PADDLETEST_PATH`
2. **Confusing test file formats** — Unit tests use full path (`test/legacy_test/test_*.py`), PaddleTest uses module names (`test_layer_norm.py`)
3. **Manually setting FLAGS_use_accuracy_compatible_kernel** — All scripts set this internally, don't duplicate
