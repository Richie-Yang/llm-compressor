"""INT4 weight-only (W4A16) with GPTQ. Needs calibration data."""
from common import calibration_kwargs, load, parse_args, save
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import GPTQModifier

args = parse_args(__doc__, calibrated=True)
model, tokenizer = load(args)

recipe = GPTQModifier(targets="Linear", scheme="W4A16", ignore=args.ignore)
oneshot(model=model, recipe=recipe, **calibration_kwargs(args))

save(model, tokenizer, args, "W4A16-GPTQ")
