"""INT4 weight-only (W4A16) with AWQ (activation-aware weight scaling). Needs calibration data."""
from common import calibration_kwargs, load, parse_args, save
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import QuantizationModifier
from llmcompressor.modifiers.transform import AWQModifier

args = parse_args(__doc__, calibrated=True)
model, tokenizer = load(args)

# AWQ only rescales activation channels; QuantizationModifier does the actual W4A16 compression.
recipe = [
    AWQModifier(),
    QuantizationModifier(targets="Linear", scheme="W4A16", ignore=args.ignore),
]
oneshot(model=model, recipe=recipe, **calibration_kwargs(args))

save(model, tokenizer, args, "W4A16-AWQ")
