"""FP8 W8A8 with dynamic per-token activation scales. Data-free: no calibration set needed."""
from common import load, parse_args, save
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import QuantizationModifier

args = parse_args(__doc__, calibrated=False)
model, tokenizer = load(args)

recipe = QuantizationModifier(targets="Linear", scheme="FP8_DYNAMIC", ignore=args.ignore)
oneshot(model=model, recipe=recipe)

save(model, tokenizer, args, "FP8-Dynamic")
