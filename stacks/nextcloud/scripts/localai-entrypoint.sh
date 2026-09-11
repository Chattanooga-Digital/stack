#!/bin/sh
# Entrypoint for LocalAI.
#
# LocalAI v4 ships an EMPTY /backends, and /v1/models still advertises the model,
# so readiness passes and the request fails "backend not found: whisper". The
# backend is installed here, into a volume, so it downloads once.
# README: "LocalAI backends".
#
# A failed install must NOT kill the service -- LocalAI still serves everything
# else -- but it must be LOUD, because the symptom otherwise appears much later
# as a transcription failure with no obvious cause.
if [ ! -d /backends/whisper ]; then
  echo "[localai] installing whisper backend"
  if /local-ai backends install whisper; then
    echo "[localai] whisper backend installed"
  else
    echo "[localai] WHISPER BACKEND INSTALL FAILED -- /v1/models will still advertise" >&2
    echo "[localai] the model and transcription will fail with 'backend not found'." >&2
  fi
fi

exec /entrypoint.sh
