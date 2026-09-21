"""Shared helpers for the quantize_*.py scripts (run inside the llm-compressor image)."""
import argparse
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


def save(model, tokenizer, args, suffix):
    out = Path(args.output_dir) / f"{Path(args.model_id).name}-{suffix}"
    model.save_pretrained(out, save_compressed=True)
    tokenizer.save_pretrained(out)
    print(f"saved {out}")
