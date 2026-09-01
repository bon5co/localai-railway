#!/bin/bash
# Boot LocalAI on Railway.
#
#   1. Refuse to start without an API key. LocalAI serves inference and its web
#      UI to anyone when no key is set, and the URL is public from the moment
#      Railway assigns the domain.
#   2. Seed the baked backend and model onto the volume. A Railway volume is a
#      bind mount, so it hides whatever the image build wrote under its path.
#   3. Bind the port Railway injected. LocalAI reads $LOCALAI_ADDRESS, never
#      $PORT, and Railway's healthcheck dials the injected port.
#   4. Size the llama.cpp thread pool from the cgroup quota instead of the
#      host's core count, which a container always over-reports.
#   5. Load the default model before the first request rather than during it.
set -euo pipefail

log() { echo "[railway-entrypoint] $*"; }

if [ -z "${LOCALAI_API_KEY:-}" ]; then
  echo "[railway-entrypoint] FATAL: LOCALAI_API_KEY is empty. Refusing to start:" >&2
  echo "[railway-entrypoint] LocalAI would serve inference and the web UI to anyone with the URL." >&2
  exit 1
fi

SEED_SOURCE="${LOCALAI_SEED_SOURCE:-/opt/localai}"

seed() { # seed <name> <destination>
  local name="$1" dest="$2" src="${SEED_SOURCE}/$1"
  mkdir -p "$dest"
  [ -d "$src" ] || return 0
  local entry base
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    base="$(basename "$entry")"
    if [ -e "$dest/$base" ]; then
      continue
    fi
    cp -a "$entry" "$dest/$base"
    log "seeded $name/$base onto the volume"
  done
}

seed backends "${LOCALAI_BACKENDS_PATH:-/data/backends}"
seed models "${LOCALAI_MODELS_PATH:-/data/models}"
mkdir -p "${LOCALAI_CONFIG_DIR:-/data/configuration}" \
         "${LOCALAI_DATA_PATH:-/data/state}" \
         "${LOCALAI_UPLOAD_PATH:-/data/uploads}" \
         "${LOCALAI_GENERATED_CONTENT_PATH:-/data/generated}"

PORT="${PORT:-8080}"
export LOCALAI_ADDRESS=":${PORT}"

# cpu.max is "<quota> <period>", or "max <period>" when the cgroup is unlimited.
cpus=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r quota period < /sys/fs/cgroup/cpu.max || true
  if [ "${quota:-max}" != "max" ] && [ -n "${period:-}" ]; then
    cpus=$(( (quota + period - 1) / period ))
  fi
fi
[ -n "$cpus" ] || cpus="$(nproc)"
[ "$cpus" -ge 1 ] || cpus=1
if [ -z "${LOCALAI_THREADS:-}${THREADS:-}" ]; then
  export LOCALAI_THREADS="$cpus"
fi
log "cpu_quota=${cpus} threads=${LOCALAI_THREADS:-${THREADS:-}} address=${LOCALAI_ADDRESS}"

# Warm the default model so the first caller does not pay for the load.
if [ -n "${LOCALAI_DEFAULT_MODEL:-}" ] && [ "${LOCALAI_WARMUP:-true}" = "true" ]; then
  (
    for _ in $(seq 1 120); do
      if curl -fsS -m 5 "http://127.0.0.1:${PORT}/readyz" >/dev/null 2>&1; then
        curl -fsS -m 600 -o /dev/null \
          -H "Authorization: Bearer ${LOCALAI_API_KEY}" \
          -H 'Content-Type: application/json' \
          -d "{\"model\":\"${LOCALAI_DEFAULT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" \
          "http://127.0.0.1:${PORT}/v1/chat/completions" >/dev/null 2>&1 \
          && log "warmup complete: ${LOCALAI_DEFAULT_MODEL} is loaded" \
          || log "warmup request failed; the model loads on the first real request"
        exit 0
      fi
      sleep 2
    done
    log "warmup skipped: server did not become ready in time"
  ) &
fi

exec /local-ai "$@"
