# syntax=docker/dockerfile:1

FROM nvcr.io/nvidia/pytorch:26.04-py3

ARG LLMCOMPRESSOR_VERSION=0.13.0

WORKDIR /opt/app

# The NGC image sets its own PIP_CONSTRAINT (e.g. numpy<=2.1). Replace it with the
# exact GPU-tuned builds shipped in this base image so pip cannot swap them for
# CPU/x86 wheels. transformers is deliberately left unconstrained: llmcompressor
# needs a newer one than NGC ships.
RUN pip list --format=freeze 2>/dev/null \
      | grep -i -E '^(torch|torchvision|torchaudio|triton|numpy)==' > /tmp/constraints.txt \
    && cat /tmp/constraints.txt \
    && grep -q '^torch==' /tmp/constraints.txt \
    && PIP_CONSTRAINT=/tmp/constraints.txt \
       pip install --no-cache-dir "llmcompressor==${LLMCOMPRESSOR_VERSION}" \
    && rm -f /tmp/constraints.txt

COPY smoke_test.py .

CMD ["python", "smoke_test.py"]
