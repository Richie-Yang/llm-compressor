"""NVFP4 (4-bit float weights + activations, Blackwell-native). Needs calibration data for activation scales."""
from common import calibration_kwargs, load, parse_args, save
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import QuantizationModifier

args = parse_args(__doc__, calibrated=True)
model, tokenizer = load(args.model_id)

recipe = QuantizationModifier(targets="Linear", scheme="NVFP4", ignore=args.ignore)
oneshot(model=model, recipe=recipe, **calibration_kwargs(args))

save(model, tokenizer, args, "NVFP4")
