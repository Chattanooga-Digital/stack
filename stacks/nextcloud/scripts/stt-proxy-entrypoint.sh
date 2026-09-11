#!/bin/sh
# Entrypoint for the speech-to-text proxy.
#
# ffmpeg is what makes this a transcoder rather than a relay: Talk hands over a
# recording container and whisper wants 16 kHz mono. Installed at start rather
# than baked into an image, because an image for sixty lines of Python costs more
# than it saves.
#
# A FAILED INSTALL MUST NOT KILL THE SERVICE: the proxy still starts and reports
# ffmpeg=MISSING, which is diagnosable. Exiting would give a restart loop whose
# logs never mention the network.
apk add --no-cache ffmpeg >/dev/null 2>&1 || echo "[stt-proxy] ffmpeg install FAILED"

exec python3 /proxy.py
