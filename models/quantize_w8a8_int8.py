"""INT8 W8A8: SmoothQuant (migrates activation outliers into weights) then GPTQ. Needs calibration data."""
from common import calibration_kwargs, load, parse_args, save
from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import GPTQModifier
from llmcompressor.modifiers.transform import SmoothQuantModifier

args = parse_args(__doc__, calibrated=True)
model, tokenizer = load(args.model_id)

recipe = [
    SmoothQuantModifier(smoothing_strength=0.8),
    GPTQModifier(targets="Linear", scheme="W8A8", ignore=args.ignore),
]
oneshot(model=model, recipe=recipe, **calibration_kwargs(args))

save(model, tokenizer, args, "W8A8-INT8")
