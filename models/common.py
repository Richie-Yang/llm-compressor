"""Shared helpers for the quantize_*.py scripts (run inside the llm-compressor image)."""
import argparse
import atexit
import contextlib
import os
import shutil
from pathlib import Path

from transformers import AutoModelForCausalLM, AutoTokenizer


def parse_args(description, calibrated):
    p = argparse.ArgumentParser(description=description)
    p.add_argument("model_id", help="Hugging Face model id or a local path")
    p.add_argument("--output-dir", default="/models/output",
                   help="parent directory for the result (default: %(default)s)")
    p.add_argument("--ignore", nargs="*", default=["lm_head"],
                   help="module names/patterns left unquantized (default: %(default)s)")
    p.add_argument("--offload-dir", default=None,
                   help="for models bigger than RAM: keep weights beyond --max-cpu-memory on disk here and "
                        "stream them layer by layer (scratch dir, removed afterwards; needs disk space "
                        "about the size of the model)")
    p.add_argument("--max-cpu-memory", default="24GiB",
                   help="with --offload-dir: RAM budget for weights, the rest goes to disk. Whole GiB/MiB "
                        "values, e.g. 24GiB or 500MiB; must be larger than the biggest single layer or the "
                        "embedding table (default: %(default)s)")
    p.add_argument("--max-shard-size", default=None,
                   help="safetensors shard size when saving, e.g. 5GB (default: 5GB with --offload-dir, "
                        "since saving an offloaded model needs free RAM of about one shard)")
    if calibrated:
        p.add_argument("--dataset", default="open_platypus",
                       help="built-in calibration dataset, e.g. open_platypus, ultrachat_200k, c4 "
                            "(default: %(default)s)")
        p.add_argument("--num-samples", type=int, default=512,
                       help="calibration samples (default: %(default)s)")
        p.add_argument("--max-seq-len", type=int, default=2048,
                       help="calibration sequence length (default: %(default)s)")
    return p.parse_args()


def _report_offload(model):
    kinds = [type(m._parameters).__name__ for m in model.modules()]
    print(f"offload: {kinds.count('DiskCache')} modules on disk, {kinds.count('CPUCache')} in RAM")


def load(args):
    kwargs, ctx = dict(dtype="auto"), contextlib.nullcontext()
    if args.offload_dir:
        from llmcompressor.utils.dev import load_context

        offload = Path(args.offload_dir)
        if not offload.exists():  # scratch space we create, so we clean it up
            atexit.register(shutil.rmtree, offload, ignore_errors=True)
        kwargs.update(
            device_map="auto_offload",
            offload_folder=str(offload),
            max_memory={"cpu": args.max_cpu_memory},
        )
        ctx = load_context()
    with ctx:
        model = AutoModelForCausalLM.from_pretrained(args.model_id, **kwargs)
    tokenizer = AutoTokenizer.from_pretrained(args.model_id)
    if args.offload_dir:
        _report_offload(model)
    return model, tokenizer


def calibration_kwargs(args):
    return dict(
        dataset=args.dataset,
        num_calibration_samples=args.num_samples,
        max_seq_length=args.max_seq_len,
    )


def _open_permissions(path):
    """chmod 777 path and everything below it (the container writes as root)."""
    os.chmod(path, 0o777)
    for root, dirs, files in os.walk(path):
        for name in dirs + files:
            os.chmod(os.path.join(root, name), 0o777)


def save(model, tokenizer, args, suffix):
    parent = Path(args.output_dir)
    parent_is_new = not parent.exists()
    out = parent / f"{Path(args.model_id).name}-{suffix}"
    save_kwargs = {}
    if args.offload_dir:
        # transformers 5.14 crashes when saving a sharded, offloaded model unless it skips reverting
        # weight conversions. Dense models (Llama, Qwen, ...) have none, so their output is unchanged.
        save_kwargs["save_original_format"] = False
    shard = args.max_shard_size or ("5GB" if args.offload_dir else None)
    if shard:
        save_kwargs["max_shard_size"] = shard
    model.save_pretrained(out, save_compressed=True, **save_kwargs)
    tokenizer.save_pretrained(out)
    if parent_is_new:  # so model folders under it can be deleted without root
        os.chmod(parent, 0o777)
    _open_permissions(out)
    print(f"saved {out}")
