#!/bin/sh
# Entrypoint for the speech-to-text proxy.
#
# ffmpeg is what makes this a transcoder rather than a relay: Talk hands over a
# recording container, and whisper wants 16 kHz mono audio. It is installed at
# start rather than baked into an image, because building, hosting and patching
# an image for sixty lines of Python costs more than it saves.
#
# A FAILED INSTALL MUST NOT KILL THE SERVICE. If apk cannot reach the index the
# proxy still starts and reports ffmpeg=MISSING on its health output, which is a
# diagnosable state. Exiting here instead would put the task in a restart loop
# whose logs say nothing about the network being the cause.
#
# This lived inline in the compose file as a four-line `command:` until 2026-09-10.
# It moved for CONVENTIONS.md ("No long inline commands"), the same reason
# taskworker.sh and recording-share.sh moved, and because `$` in an inline
# command has to be written `$$` -- a rule that silently produces empty strings
# when missed.
apk add --no-cache ffmpeg >/dev/null 2>&1 || echo "[stt-proxy] ffmpeg install FAILED"

exec python3 /proxy.py
