"""Shared helpers for the quantize_*.py scripts (run inside the llm-compressor image)."""
import argparse
import os
from pathlib import Path

from transformers import AutoModelForCausalLM, AutoTokenizer


def parse_args(description, calibrated):
    p = argparse.ArgumentParser(description=description)
    p.add_argument("model_id", help="Hugging Face model id or a local path")
    p.add_argument("--output-dir", default="/models/output",
                   help="parent directory for the result (default: %(default)s)")
    p.add_argument("--ignore", nargs="*", default=["lm_head"],
                   help="module names/patterns left unquantized (default: %(default)s)")
    if calibrated:
        p.add_argument("--dataset", default="open_platypus",
                       help="built-in calibration dataset, e.g. open_platypus, ultrachat_200k, c4 "
                            "(default: %(default)s)")
        p.add_argument("--num-samples", type=int, default=512,
                       help="calibration samples (default: %(default)s)")
        p.add_argument("--max-seq-len", type=int, default=2048,
                       help="calibration sequence length (default: %(default)s)")
    return p.parse_args()


def load(model_id):
    model = AutoModelForCausalLM.from_pretrained(model_id, dtype="auto")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
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
    model.save_pretrained(out, save_compressed=True)
    tokenizer.save_pretrained(out)
    if parent_is_new:  # so model folders under it can be deleted without root
        os.chmod(parent, 0o777)
    _open_permissions(out)
    print(f"saved {out}")
