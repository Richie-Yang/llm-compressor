#!/usr/bin/env bash
# Host-side tests for the llm-compressor image.
# Usage: tests/test_image.sh [test_name ...]   (default: run every test)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$DIR/docker-compose.yml")
FAILED=0

SKIP_RC=77

run() {
  local name=$1 rc
  echo "=== $name"
  "$name"; rc=$?
  case $rc in
    0) echo "PASS $name" ;;
    $SKIP_RC) echo "SKIP $name" ;;
    *) echo "FAIL $name"; FAILED=1 ;;
  esac
}

test_compose_config() {
  local cfg
  cfg=$("${COMPOSE[@]}" config 2>&1) || { echo "$cfg"; return 1; }
  grep -q 'llm-compressor:' <<<"$cfg" || { echo "service llm-compressor missing"; return 1; }
  grep -q 'driver: nvidia' <<<"$cfg" || { echo "nvidia GPU reservation missing"; return 1; }
  grep -q 'target: /root/.cache/huggingface' <<<"$cfg" || { echo "HF cache mount missing"; return 1; }
  grep -q 'target: /models' <<<"$cfg" || { echo "/models mount missing"; return 1; }
}

test_image_builds() {
  local log rc
  log=$(mktemp)
  "${COMPOSE[@]}" build >"$log" 2>&1; rc=$?
  tail -n 15 "$log"; rm -f "$log"
  return $rc
}

test_smoke_prints_version() {
  local out rc
  out=$("${COMPOSE[@]}" run --rm llm-compressor 2>&1); rc=$?
  echo "$out" | tail -n 15
  [ $rc -eq 0 ] || { echo "smoke test exited $rc"; return 1; }
  grep -q '^llmcompressor 0.13.0$' <<<"$out" || { echo "expected 'llmcompressor 0.13.0'"; return 1; }
}

test_torch_is_ngc_build() {
  local out
  out=$("${COMPOSE[@]}" run --rm llm-compressor 2>&1) || { echo "$out" | tail -n 15; return 1; }
  grep -E -q '^torch [0-9][^ ]*\.nv[0-9]' <<<"$out" \
    || { echo "$out" | tail -n 5; echo "expected 'torch <ver>.nvNN' (NGC build)"; return 1; }
}

test_gpu_visible_via_compose() {
  local out
  out=$("${COMPOSE[@]}" run --rm llm-compressor 2>&1) || { echo "$out" | tail -n 15; return 1; }
  grep -q '^cuda available: True$' <<<"$out" || { echo "$out" | tail -n 5; echo "expected 'cuda available: True'"; return 1; }
  grep -q '^gpu: .' <<<"$out" || { echo "expected a 'gpu: <name>' line"; return 1; }
}

test_smoke_fails_without_gpu() {
  local out rc
  out=$(docker run --rm --runtime=runc "llm-compressor:${LLMCOMPRESSOR_VERSION:-0.13.0}" 2>&1); rc=$?
  echo "$out" | tail -n 5
  [ $rc -ne 0 ] || { echo "expected non-zero exit when no GPU is exposed"; return 1; }
  grep -q 'CUDA is not available' <<<"$out" || { echo "expected 'CUDA is not available' message"; return 1; }
}

test_models_mount_persists() {
  local tmp target rc=0 image="llm-compressor:${LLMCOMPRESSOR_VERSION:-0.13.0}"
  tmp=$(mktemp -d)
  target="$tmp/not-created-yet"   # host dir does not exist beforehand
  MODELS_DIR="$target" "${COMPOSE[@]}" run --rm llm-compressor \
    bash -c 'echo hello > /models/probe.txt' >/dev/null 2>&1
  if [ "$(cat "$target/probe.txt" 2>/dev/null)" != "hello" ]; then
    echo "probe.txt did not appear in $target"; rc=1
  fi
  # Docker created $target as root; remove it from inside a container.
  docker run --rm --runtime=runc -v "$tmp:/t" --entrypoint sh "$image" -c 'rm -rf /t/not-created-yet' >/dev/null 2>&1
  rmdir "$tmp"
  return $rc
}

# Slow tests: download a small model + calibration data and quantize it for real.
# Opt in with SLOW=1 (needs network). TEST_MODEL overrides the model.
check_quantize_script() {
  local script=$1 suffix=$2 fmt=$3 calib=${4:-yes}   # calib=no for data-free scripts (no calibration flags)
  local model=${TEST_MODEL:-Qwen/Qwen2.5-0.5B-Instruct} out rc=0 image="llm-compressor:${LLMCOMPRESSOR_VERSION:-0.13.0}"
  local extra=()
  [ "${SLOW:-0}" = 1 ] || { echo "skipped (set SLOW=1)"; return $SKIP_RC; }
  [ "$calib" = yes ] && extra=(--num-samples 8 --max-seq-len 256)
  out=$(mktemp -d)
  "${COMPOSE[@]}" run --rm -v "$out:/out" llm-compressor \
    python "/models/$script" "$model" --output-dir /out "${extra[@]}" 2>&1 | tail -n 5
  local cfg="$out/${model##*/}-$suffix/config.json"
  if [ ! -f "$cfg" ]; then echo "missing $cfg"; rc=1
  elif ! grep -q '"quant_method": "compressed-tensors"' "$cfg"; then echo "no compressed-tensors quantization_config in $cfg"; rc=1
  elif ! grep -q "\"format\": \"$fmt\"" "$cfg"; then echo "expected quantization format '$fmt' in $cfg"; rc=1
  elif [ -n "$(find "$out/${model##*/}-$suffix" -not -perm 0777)" ]; then
    echo "expected every file/dir in the output to be mode 777, found:"
    find "$out/${model##*/}-$suffix" -not -perm 0777 -printf '%m %p\n' | head -5; rc=1
  fi
  # Container wrote as root; remove from inside a container.
  docker run --rm --runtime=runc -v "$out:/t" --entrypoint sh "$image" -c 'rm -rf /t/* /t/.[!.]*' >/dev/null 2>&1
  rmdir "$out"
  return $rc
}

test_quantize_fp8_dynamic() { check_quantize_script quantize_fp8_dynamic.py FP8-Dynamic float-quantized no; }
test_quantize_w8a8_int8()   { check_quantize_script quantize_w8a8_int8.py   W8A8-INT8 int-quantized; }
test_quantize_w4a16_gptq()  { check_quantize_script quantize_w4a16_gptq.py  W4A16-GPTQ pack-quantized; }
test_quantize_w4a16_awq()   { check_quantize_script quantize_w4a16_awq.py   W4A16-AWQ pack-quantized; }
test_quantize_nvfp4()       { check_quantize_script quantize_nvfp4.py       NVFP4 nvfp4-pack-quantized; }

# Offload tests (SLOW): force the disk-offload path on a tiny model with a tiny RAM budget.
offload_run() {   # offload_run <out_dir> <script> [args...]; prints the script's combined output
  local out=$1 script=$2; shift 2
  "${COMPOSE[@]}" run --rm -T -v "$out:/out" llm-compressor \
    python "/models/$script" "${TEST_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}" --output-dir /out "$@" 2>&1
}
root_rmdir() {    # remove a directory tree the container wrote as root
  docker run --rm --runtime=runc -v "$1:/t" --entrypoint sh "llm-compressor:${LLMCOMPRESSOR_VERSION:-0.13.0}" \
    -c 'rm -rf /t/* /t/.[!.]*' >/dev/null 2>&1
  rmdir "$1"
}
disk_offloaded() { awk '/^offload: /{ if ($2+0 > 0) ok=1 } END{exit !ok}'; }   # "offload: <n> modules on disk, <m> in RAM"

test_offload_uses_disk_and_cleans_up() {
  [ "${SLOW:-0}" = 1 ] || { echo "skipped (set SLOW=1)"; return $SKIP_RC; }
  local out log rc=0 model=${TEST_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}
  out=$(mktemp -d)
  log=$(offload_run "$out" quantize_fp8_dynamic.py --offload-dir /out/offload --max-cpu-memory 500MiB --max-shard-size 300MB) || { echo "$log" | tail -n 8; rc=1; }
  if [ $rc -eq 0 ]; then
    disk_offloaded <<<"$log" || { echo "expected an 'offload: <n> modules on disk, ...' line with n > 0"; rc=1; }
    grep -q '"format": "float-quantized"' "$out/${model##*/}-FP8-Dynamic/config.json" 2>/dev/null || { echo "output missing or wrong format"; rc=1; }
    [ ! -e "$out/offload" ] || { echo "offload scratch dir was not removed"; rc=1; }
    [ "$(ls "$out/${model##*/}-FP8-Dynamic"/*.safetensors 2>/dev/null | wc -l)" -ge 2 ] || { echo "expected several safetensors shards with --max-shard-size 300MB"; rc=1; }
  fi
  root_rmdir "$out"
  return $rc
}

test_offload_matches_plain() {
  [ "${SLOW:-0}" = 1 ] || { echo "skipped (set SLOW=1)"; return $SKIP_RC; }
  local a b rc=0 name=${TEST_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}; name="${name##*/}-FP8-Dynamic"
  a=$(mktemp -d); b=$(mktemp -d)
  offload_run "$a" quantize_fp8_dynamic.py >/dev/null || { echo "plain run failed"; rc=1; }
  offload_run "$b" quantize_fp8_dynamic.py --offload-dir /out/offload --max-cpu-memory 500MiB >/dev/null || { echo "offload run failed"; rc=1; }
  if [ $rc -eq 0 ]; then
    "${COMPOSE[@]}" run --rm -T -v "$a:/a:ro" -v "$b:/b:ro" -e NAME="$name" llm-compressor python - <<'EOF' 2>&1 | tail -n 3 || rc=1
import glob, os, sys, torch
from safetensors.torch import load_file
def load(root):
    t = {}
    for f in sorted(glob.glob(f"{root}/{os.environ['NAME']}/*.safetensors")):
        t.update(load_file(f))
    return t
a, b = load("/a"), load("/b")
assert a.keys() == b.keys(), f"tensor names differ: {sorted(a.keys() ^ b.keys())[:5]}"
raw = lambda x: x.reshape(-1).contiguous().view(torch.uint8)
bad = [k for k in a if a[k].dtype != b[k].dtype or a[k].shape != b[k].shape or not torch.equal(raw(a[k]), raw(b[k]))]
assert not bad, f"{len(bad)} tensors differ, e.g. {bad[:3]}"
print(f"IDENTICAL: {len(a)} tensors")
EOF
  fi
  root_rmdir "$a"; root_rmdir "$b"
  return $rc
}

test_offload_calibrated_gptq() {
  [ "${SLOW:-0}" = 1 ] || { echo "skipped (set SLOW=1)"; return $SKIP_RC; }
  local out log rc=0 model=${TEST_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}
  out=$(mktemp -d)
  log=$(offload_run "$out" quantize_w4a16_gptq.py --num-samples 8 --max-seq-len 256 \
        --offload-dir /out/offload --max-cpu-memory 500MiB) || { echo "$log" | tail -n 8; rc=1; }
  if [ $rc -eq 0 ]; then
    disk_offloaded <<<"$log" || { echo "expected 'offload: <n> modules on disk' with n > 0"; rc=1; }
    grep -q '"format": "pack-quantized"' "$out/${model##*/}-W4A16-GPTQ/config.json" 2>/dev/null || { echo "output missing or wrong format"; rc=1; }
  fi
  root_rmdir "$out"
  return $rc
}

TESTS=(test_compose_config test_image_builds test_smoke_prints_version
       test_torch_is_ngc_build test_gpu_visible_via_compose
       test_smoke_fails_without_gpu test_models_mount_persists
       test_quantize_fp8_dynamic test_quantize_w8a8_int8 test_quantize_w4a16_gptq
       test_quantize_w4a16_awq test_quantize_nvfp4
       test_offload_uses_disk_and_cleans_up test_offload_matches_plain test_offload_calibrated_gptq)
if [ $# -gt 0 ]; then TESTS=("$@"); fi
for t in "${TESTS[@]}"; do run "$t"; done
exit $FAILED
