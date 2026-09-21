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

### Choosing a scheme

Sizes are relative to the BF16 original. Speed and accuracy depend on the model, the inference engine
(e.g. vLLM) and its kernels for your GPU, so evaluate the result on your own task before switching.

**FP8 Dynamic** (`quantize_fp8_dynamic.py`), about 2x smaller
- Pros: no calibration data; quantizes in minutes; usually the smallest accuracy loss; activation scales are computed at runtime, so there is nothing to tune
- Cons: only about 2x compression; real compute speedup needs FP8 hardware (Ada, Hopper, Blackwell); dynamic scaling adds a little runtime overhead

**INT8 W8A8** (`quantize_w8a8_int8.py`), about 2x smaller
- Pros: INT8 tensor cores exist on more GPUs (Ampere and later), so it is the 8-bit option where FP8 is unavailable; quantized weights and activations speed up compute-bound work such as large batches and prefill
- Cons: needs calibration data; SmoothQuant + GPTQ makes it slower to quantize than FP8; activation outliers make it more accuracy-sensitive; SmoothQuant needs layer mappings, which may not exist for unusual architectures; on FP8-capable GPUs, FP8 is generally the simpler choice

**W4A16 GPTQ** (`quantize_w4a16_gptq.py`), about 3.5-4x smaller
- Pros: biggest memory saving of the weight-only options, so larger models fit and low-batch decoding (memory-bound) gets faster; GPTQ's error compensation keeps 4-bit accuracy good
- Cons: activations stay 16-bit, so there is no compute speedup, and large batches or prefill can be slower than BF16; needs calibration data and the result depends on its quality (it can overfit the calibration set); slowest and most memory-hungry to quantize; larger accuracy loss than 8-bit, especially on small models

**W4A16 AWQ** (`quantize_w4a16_awq.py`), about 3.5-4x smaller
- Pros: same size and runtime characteristics as GPTQ; protects the channels that matter most to activations and tends to overfit the calibration set less; often quicker to quantize
- Cons: same weight-only limits as GPTQ (no compute speedup, needs calibration data); AWQ needs layer mappings, which may not exist for unusual architectures; accuracy versus GPTQ varies by model, so try both if it matters

**NVFP4** (`quantize_nvfp4.py`), about 3.5-4x smaller
- Pros: Blackwell-native 4-bit float for both weights and activations, so it can cut memory and speed up compute on the GB10; per-block scales keep accuracy better than plain 4-bit integer activations
- Cons: needs Blackwell, and your inference engine must ship FP4 kernels for that GPU; needs calibration data for activation scales; 4-bit activations lose more accuracy than the 8-bit schemes, especially on small models; newest and least mature of the formats

Rule of thumb: start with FP8 Dynamic. Go to W4A16 when memory is the limit, and to NVFP4 when you need 4-bit
speed on Blackwell and your engine supports it.

### Models bigger than RAM (disk offload)

A 70B model in BF16 is about 141 GB, more than this machine's 119 GB, so it cannot be loaded whole. With
`--offload-dir` the scripts keep only a RAM budget of weights in memory and leave the rest on disk, and
llm-compressor streams them in layer by layer. All five scripts accept these flags:

| Flag                | Default            | Meaning                                                                                  |
| ------------------- | ------------------ | ---------------------------------------------------------------------------------------- |
| `--offload-dir`     | off                | scratch folder on disk; setting it turns offloading on; deleted when the script exits     |
| `--max-cpu-memory`  | `24GiB`            | RAM budget for weights (whole `GiB`/`MiB`); the rest goes to disk                         |
| `--max-shard-size`  | `5GB` if offloading | size of each saved safetensors file                                                      |

```bash
docker compose run --rm llm-compressor python /models/quantize_w4a16_gptq.py aaditya/Llama3-OpenBioLLM-70B \
  --offload-dir /models/offload --max-cpu-memory 24GiB
```

Things to know:
- **Unified memory:** on the GB10 the GPU and CPU share the same RAM, so keep `--max-cpu-memory` well below the
  free memory (other containers such as the running vLLM service use a lot). The budget must be larger than the
  biggest single layer or the embedding table.
- **Disk:** the scratch folder holds roughly the model size minus the RAM budget (about 115 GB for a 70B at
  24GiB), plus the output. It sits under `./models` when you use `/models/offload`. If a run is killed it can be
  left behind as a root-owned folder; remove it with `docker run --rm -v $PWD/models:/m --entrypoint rm llm-compressor:0.13.0 -rf /m/offload`.
- **Speed:** slow, because weights are re-read from disk for each layer. Expect hours for a 70B.
- **Saving:** offloaded models are saved with `save_original_format=False` to work around a transformers 5.14
  crash on sharded saves. Dense models (Llama, Qwen, ...) are unaffected and produce identical tensors (checked
  by a test). Mixture-of-experts models may be saved in transformers 5's in-memory layout, which older readers,
  including the vLLM image, may not understand; check before relying on it.
- **Tested on** a 0.5B model with a tiny RAM budget (FP8 output is byte-identical to a normal run; GPTQ
  works too). It has not been run on a 70B, so treat a first 70B run as an experiment and stop other memory-heavy
  containers first.

## Mounts

| Host (override with)                                 | Container                  | Purpose                        |
| ---------------------------------------------------- | -------------------------- | ------------------------------ |
| `~/.cache/huggingface` (`HF_CACHE_DIR`)              | `/root/.cache/huggingface` | reuse downloaded models        |
| `./models` (`MODELS_DIR`)                            | `/models`                  | scripts and compressed outputs |

Docker creates a missing `./models` as root-owned. Files written by the container are root-owned too, but the
quantize scripts `chmod 777` each saved model folder (and `output/` if they created it), so anyone can read,
modify and delete them.

## Tests

```bash
tests/test_image.sh                       # all (the quantization tests are skipped)
tests/test_image.sh test_compose_config   # one
SLOW=1 tests/test_image.sh                # also run every quantize script on a small model (needs network)
```

Needs Docker with the `nvidia` runtime and a GPU. The first build pulls the ~20 GB NGC base image.
`SLOW=1` downloads `Qwen/Qwen2.5-0.5B-Instruct` (override with `TEST_MODEL`) and a calibration dataset.
