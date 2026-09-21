# llm-compressor

Docker image for [`llmcompressor`](https://github.com/vllm-project/llm-compressor) on the GB10 (aarch64, Blackwell) host.

- Base: `nvcr.io/nvidia/pytorch:26.04-py3` (NGC's GPU-tuned `torch` is kept; pip is constrained so it cannot be replaced)
- `llmcompressor` version is pinned (default `0.13.0`), `transformers` upgrades to whatever that release needs

## Build

```bash
docker compose build
# other llmcompressor release:
LLMCOMPRESSOR_VERSION=0.12.0 docker compose build
```

The image is tagged `llm-compressor:<version>`.

## Run

The default command is a smoke test (prints the llmcompressor and torch versions, requires a visible GPU):

```bash
docker compose run --rm llm-compressor
```

Run your own script or shell by overriding the command:

```bash
docker compose run --rm llm-compressor bash
docker compose run --rm llm-compressor python /models/my_script.py
```

## Quantization scripts

Ready-made scripts live in `models/` (mounted at `/models`) and work for standard text-only causal LMs.
Pass a Hugging Face model id or a local path; the result goes to `models/output/<model>-<suffix>`.

| Script                     | Scheme (output suffix)         | Calibration data | Notes                                      |
| -------------------------- | ------------------------------ | ---------------- | ------------------------------------------ |
| `quantize_fp8_dynamic.py`  | FP8 W8A8 (`FP8-Dynamic`)       | no               | simplest; good first run                   |
| `quantize_w8a8_int8.py`    | INT8 W8A8 (`W8A8-INT8`)        | yes              | SmoothQuant + GPTQ                         |
| `quantize_w4a16_gptq.py`   | INT4 weights (`W4A16-GPTQ`)    | yes              | smallest size, weight-only                 |
| `quantize_w4a16_awq.py`    | INT4 weights (`W4A16-AWQ`)     | yes              | AWQ scaling + W4A16                        |
| `quantize_nvfp4.py`        | NVFP4 (`NVFP4`)                | yes              | Blackwell-native (GB10)                    |

```bash
docker compose run --rm llm-compressor python /models/quantize_fp8_dynamic.py Qwen/Qwen2.5-7B-Instruct
docker compose run --rm llm-compressor python /models/quantize_w4a16_gptq.py Qwen/Qwen2.5-7B-Instruct --num-samples 256
docker compose run --rm llm-compressor python /models/quantize_nvfp4.py --help
```

Common flags: `--output-dir`, `--ignore` (modules to skip, default `lm_head`). Calibrated scripts also take
`--dataset` (built-in name: `open_platypus` default, `ultrachat_200k`, `c4`, ...), `--num-samples` (512) and
`--max-seq-len` (2048). MoE and vision-language models need a longer `--ignore` list or a different model
class, so these scripts are not a drop-in for them.

## Mounts

| Host (override with)                                 | Container                  | Purpose                        |
| ---------------------------------------------------- | -------------------------- | ------------------------------ |
| `~/.cache/huggingface` (`HF_CACHE_DIR`)              | `/root/.cache/huggingface` | reuse downloaded models        |
| `./models` (`MODELS_DIR`)                            | `/models`                  | scripts and compressed outputs |

Docker creates a missing `./models` as root-owned; files written from the container are root-owned too.

## Tests

```bash
tests/test_image.sh                       # all (the quantization tests are skipped)
tests/test_image.sh test_compose_config   # one
SLOW=1 tests/test_image.sh                # also run every quantize script on a small model (needs network)
```

Needs Docker with the `nvidia` runtime and a GPU. The first build pulls the ~20 GB NGC base image.
`SLOW=1` downloads `Qwen/Qwen2.5-0.5B-Instruct` (override with `TEST_MODEL`) and a calibration dataset.
