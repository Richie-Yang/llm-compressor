import importlib.metadata
import sys

import llmcompressor  # noqa: F401  (import must succeed)
import torch

print(f"llmcompressor {importlib.metadata.version('llmcompressor')}")
print(f"torch {torch.__version__}")
print(f"cuda available: {torch.cuda.is_available()}")
if not torch.cuda.is_available():
    sys.exit("CUDA is not available: run with the nvidia runtime / a GPU reservation")
print(f"gpu: {torch.cuda.get_device_name(0)}")
