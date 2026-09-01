# LocalAI for Railway.
#
# Two things make a stock LocalAI deploy useless on Railway, and this wrapper
# exists to fix both.
#
# 1. LocalAI 4.x ships no inference backend in the image. Backends are OCI
#    artifacts pulled from a gallery at runtime, so a fresh container answers
#    every request with "backend not found: llama-cpp". The llama.cpp CPU
#    backend is installed here, at build time.
# 2. A LocalAI deploy with no model is an API with nothing behind it. A model
#    is installed here too, so the server has weights resident from the first
#    request instead of waiting on a download the deployer has to trigger.
#
# Both are baked OUTSIDE the Railway volume mount (a volume mount hides files
# the image build wrote under that path) and seeded onto the volume at boot,
# so the deployer can install more backends and models and keep them.
FROM localai/localai:v4.9.0

ARG LOCALAI_DEFAULT_MODEL=qwen3-1.7b

# Pristine copies. Not under /data, which is the Railway mount point.
ENV LOCALAI_BACKENDS_PATH=/opt/localai/backends \
    LOCALAI_MODELS_PATH=/opt/localai/models

RUN mkdir -p /opt/localai/backends /opt/localai/models \
 && /local-ai backends install cpu-llama-cpp \
 && /local-ai models install "localai@${LOCALAI_DEFAULT_MODEL}" \
 && test -d "/opt/localai/backends/cpu-llama-cpp" \
 && test -n "$(ls -A /opt/localai/models)" \
 && du -sh /opt/localai/backends /opt/localai/models

# Everything LocalAI persists lives under the single Railway volume.
ENV LOCALAI_BACKENDS_PATH=/data/backends \
    LOCALAI_MODELS_PATH=/data/models \
    LOCALAI_CONFIG_DIR=/data/configuration \
    LOCALAI_DATA_PATH=/data/state \
    LOCALAI_UPLOAD_PATH=/data/uploads \
    LOCALAI_GENERATED_CONTENT_PATH=/data/generated \
    LOCALAI_DEFAULT_MODEL=${LOCALAI_DEFAULT_MODEL} \
    LOCALAI_SEED_SOURCE=/opt/localai

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
