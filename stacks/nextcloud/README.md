# Nextcloud

Files, Office, Whiteboard and Talk. Declarative rather than
[All-in-One](https://github.com/nextcloud/all-in-one), whose mastercontainer mounts
the Docker socket, so on a shared host anyone who can admin AIO reaches every other
tenant's containers.

Installs unattended from `ADMIN_USER` and `ADMIN_PASSWORD`, with no wizard step. The
`init` service then provisions the instance, so a deploy onto empty volumes produces
the app set, Office, Whiteboard, mail and the named admins with no hand steps.

## Routing

Three routers share `DOMAIN`, separated by priority because the app's rule matches the
whole host. Office and Whiteboard are path-routed rather than given subdomains, so
neither needs a DNS record. Talk is the exception and needs its own.

| Router | Rule | Priority | Port |
|---|---|---|---|
| `${INSTANCE_NAME}-office` | `Host(DOMAIN) && PathPrefix(/browser,/hosting,/cool)` | 100 | 9980 |
| `${INSTANCE_NAME}-board` | `Host(DOMAIN) && PathPrefix(/whiteboard)` | 100 | 3002 |
| `${INSTANCE_NAME}-app` | `Host(DOMAIN)` | 10 | 80 |
| `${INSTANCE_NAME}-talk` | `Host(TALK_HOST)` | | 8081 |

## Talk relays through the turn stack

This stack runs signaling and the HPB. Relaying belongs to [turn](../turn), which has
to be deployed and reachable first. `init` writes Nextcloud's STUN, TURN and signaling
config, so there is no `occ` step to run by hand.

`TURN_HOST`, `TURN_PORT` and `TURN_SECRET` are that stack's values and have to match it
exactly. A wrong secret still passes STUN, then fails every allocation with a 401 and
logs nothing.

The talk container ships its own eturnal, which goes unused because nothing points at
it and no port is published for it.

## Decide before the first deploy

Primary storage is the `nextcloud_html` volume. `S3_*` is honoured at first install
only, so adopting object storage later is a data migration rather than a config change.

## Recording consent, and what a deploy is allowed to overwrite

Talk ships the whole consent feature and this stack used to leave it switched off.

`recording_consent` takes three values (`RecordingService`: `CONSENT_REQUIRED_NO = 0`,
`YES = 1`, `OPTIONAL = 2`). It defaulted to **0**, and 0 is not the neutral choice it looks
like: at 0 Talk **hides the per-conversation control from moderators entirely**. So a comment
saying "we leave the decision to the co-op" was describing the one setting that takes the
decision away from them. `init.sh` now seeds **2** — moderators decide per conversation, which
is what "enable or disable recording on a specific call" actually requires. Change it with
`RECORDING_CONSENT`, or in the admin panel, where it belongs.

**Seed it, do not set it.** `occ_seed` writes a key only when it is absent. The distinction the
whole script turns on:

| | re-asserted every deploy | seeded once |
|---|---|---|
| **wiring** — where a container lives, which secret it uses | `recording_servers`, `integration_openai` urls and timeouts | |
| **policy** — whether to record, transcribe, or require consent | | `call_recording`, `call_recording_transcription`, `recording_consent`, the audio2text preference |

Containers move, so wiring has to be reconciled. Policy belongs to whoever is looking at the
admin panel, and a deploy that overwrites their choice takes it away from them silently. That
was a real defect here: `call_recording_transcription` was force-written to `yes` on every
deploy over a checkbox whose upstream default is `no`.

**`recording_consent` must not be written lazily.** `Config::getRecordingConsentConfig()` reads
it through the non-lazy `IConfig::getAppValue` (`custom_apps/spreed/lib/Config.php:231`), so a
`--lazy` row would be written, shown correctly by `occ config:app:get`, and never seen by Talk.
See *The --lazy flag is load-bearing*.

## Recordings are shared to their conversation

Talk stores a recording under the recorder's own `<attachment folder>/Recording/<room
token>/` and notifies *them* to decide whether to publish it. Until somebody clicks
"Share to chat" the file is private to whoever pressed record — including the
transcript. For an ops meeting that is the wrong owner: the record of the meeting
belongs to the people who were in it.

The `recording-share` service closes that gap. Every couple of minutes it shares
finished recordings, read-only, to the one conversation they came from — never to a
user, never to a public link, never to another room. It calls Talk's own
`RecordingService::shareToChat()`, so the chat message is attributed to the file's
owner and rendered as a recording rather than a generic file, and the owner's pending
"share this?" notification is cleared.

Set `RECORDING_AUTOSHARE=0` to turn it off and get Talk's stock behaviour back.

## Why there is no "Live transcription" here

The Talk UI shows an **Enable live transcription** toggle, greyed out, in every conversation's
settings. That is expected and is not a misconfiguration. Talk ships the switch; the transcriber
is a separate ExApp container that is not installed.

It would also not replace what this stack does. `live_transcription` is a Vosk captions client
that never writes a file: `send_transcript()` pushes text over the signaling socket to the
sessions currently in the call, and `close()` drains the queue and discards it when the call
ends (verified in upstream `v2.1.3`, `ex_app/lib/spreed_client.py:541` and `:676-678`). The
transcript that exists on disk comes from Talk's own recording path instead.

Installing it would need nothing from William, since the same `manual_install` daemon route this
stack already uses for `stt_whisper2` applies. Nobody has tested that. Full reasoning, caveats,
and the separate question of `stt_whisper2` sitting at 0 replicas:
`cd-nextcloud/docs/NEXTCLOUD.md` → *Meeting transcripts, and why NOT "Live transcription"*.


## The --lazy flag is load-bearing

A key written **non-lazily** but **read** with `lazy: true` is not found, and the reader
silently gets its default. Nothing errors: `occ config:app:get` prints the value you set, the
database holds it, and the app never sees it — so the setting reads as applied from every
angle except the only one that matters.

`occ config:app:set` writes non-lazy unless told otherwise, while `integration_openai`'s admin
panel writes lazy. A value set in a script and the same value set in the UI are therefore not
the same row, and only the UI's is read.

Measured on production 2026-09-08, after an ops meeting was lost:

| key | stored | read | effect |
|---|---|---|---|
| `url` | non-lazy | non-lazy | OK — which is why requests *did* reach stt-proxy |
| `stt_url` | non-lazy | **lazy** | ignored → `sttOverrideEnabled()` false |
| `request_timeout` | non-lazy | **lazy** | ignored → 240 s |
| `default_stt_model_id` | non-lazy | **lazy** | ignored → upstream's default model |

Because `stt_url` was invisible the STT branch was never taken, so the correctly stored
`stt_request_timeout` was never consulted either. Every transcription died at exactly 240 s
with "0 bytes received" while stt-proxy was still working fine.

**The rule:** match `--lazy` to how the app *reads* the key, and check before adding one —
`grep -r "APP_ID, 'the_key'" custom_apps/<app>/lib/ | grep 'lazy: true'`.

Separately, `occ config:app:set --lazy` prompts "Confirm this action by typing 'yes'" and
`--no-interaction` returns the question's *default*, which is no — so under `set -e` it kills
the deploy. The confirmation has to be answered explicitly.

## Audit logging that records

Enabling `admin_audit` is not enough. `Actions/Action.php` logs at `info()`, and `Log.php`
falls back to `getValue('loglevel', ILogger::WARN)` — INFO (1) is below WARN (2), so every
audit entry is discarded before it reaches the file. The app reports enabled, the file exists,
and nothing is ever written: it was **zero bytes** on production on 2026-09-01 having been
enabled since 2026-08-20. That is worse than no audit log, because it reads as coverage. It
cost us the answer to "who created these accounts", which had to come from git history.

`log.condition.matches` lowers the threshold for **one app** rather than globally: `Action.php`
passes `['app' => 'admin_audit']` and `Log.php` matches on exactly that key, so the rest of the
instance stays at WARN and `nextcloud.log` does not fill with INFO noise. Rotation needs no
setting — `admin_audit`'s own Rotate job defaults `log_rotate_size` to 100 MB.

## The default contact card

Nextcloud seeds every new account with a sample contact on first login so Contacts is not an
empty screen that reads as broken. The stock card is "Leon Green, Manager at Company" — a
plausible-looking fake **person**, which in a co-op member's address book reads like somebody
they are supposed to know; the give-aways (123 Street Street, `leon@example.com`,
+999999999999) only show once it is opened. So the sample stays on and the card is ours: an
obviously-not-a-person contact for the co-op itself.

`files/defaultContact.vcf` in this directory is that card's content. **Nothing applies it
automatically** — it lives in appdata (`dav/defaultContact/defaultContact.vcf`, flagged by
`hasCustomDefaultContact` in appconfig) and survives ordinary redeploys, but `init.sh`
deliberately does not re-apply it: that needs an authenticated HTTPS PUT, and on a cold
rebuild the public URL may not have a certificate yet, so the step would fail for a reason
unrelated to what it does. A rebuild from empty volumes falls back to Leon Green — wrong, not
broken. Re-apply by hand:

```sh
curl -u "$ADMIN_USER:$ADMIN_PASSWORD" -X PUT \
  "https://$DOMAIN/apps/dav/api/defaultcontact/contact" \
  -H 'Content-Type: application/json' \
  --data "{\"contactData\": \"$(sed -z 's/\n/\\n/g' files/defaultContact.vcf)\"}"
```

Verify by creating an account, **logging in once** — the address book is created on first
login, not at creation, so checking straight after `user:add` shows no addressbooks and proves
nothing — then exporting
`/remote.php/dav/addressbooks/users/<uid>/contacts/?export`.

## Nothing processes AI tasks without the worker

`integration_openai` is a **synchronous** TaskProcessing provider, and Nextcloud runs
those only from a dedicated worker. **Cron does not run them.** Without the `taskworker`
service a Talk transcription is accepted, written to the queue as RUNNING, and sits at
progress 0 for ever — no error, no log line, nothing on the status page. It looks exactly
like a slow job.

Found 2026-09-01 on the first real meeting recording: the recording was intact, LocalAI
had the model, the provider was configured, and the job had been "running" for 25 minutes
having never contacted anything. There was nobody to run it. Starting a worker by hand
moved it in seconds. Why its `--timeout` matters is in `scripts/taskworker.sh`.

## Why LocalAI, and why stt_whisper2 was removed

`stt_whisper2` used to be declared here at `replicas: 0`, as a comparison switch. It is gone
as of 2026-09-11, and the reasoning is worth keeping so nobody re-adds it.

It is a **16.3 GB** image of CUDA libraries for a host with **no GPU**. Measured on staging it
ran at **28x slower than real time** even on its speed-optimised model — about 28 hours of
pegged CPU for a one-hour meeting — and it **OOM-killed at a 5 GB ceiling** (exit 137). At
matched accuracy it was no faster than LocalAI, which is **0.3 GB** and whose default
`whisper-1` model is whisper.cpp's quantised `ggml-base.bin` at ~140 MB. `integration_openai`
defaults its transcription model to exactly that name, so nothing needs configuring to reach it.

Measured 2026-08-29, one 8.33s sample, same node, same 2-core cap:

| engine / model | time | vs real time |
|---|---|---|
| `stt_whisper2` large-v3 | 460.8s | 55x — OOM-killed at 5G |
| `stt_whisper2` large-v3-turbo | 233.9s | 28x |
| LocalAI small-en-q5_1 | 261.3s | 31x |
| **LocalAI base-en-q5_1** | **64.3s** | **7.7x** |

It had never run in production: checked 2026-09-11, that instance had **no registered AppAPI
daemons and no ExApps at all**, so removing it needed no cleanup there.

Its registration also carried a hazard worth remembering. Any ExApp here registers as
`manual-install`, **never** `docker-install` — that form hands a container the Docker socket on
a host that is not ours, and AppAPI's own help calls it deprecated and scheduled for removal in
Nextcloud 35. `init.sh` still removes any `docker-install` daemon it finds, because one was
registered by hand on production pointing at a container that never existed and logged an error
on every admin visit to `/settings/apps`.

### LocalAI backends

LocalAI v4 ships **no backends in the image**. `/models` holds the model definition,
`/backends` holds the runtime that executes it, and the image's `/backends` is empty — and it
was not persisted, so anything installed there vanished on the next restart. The symptom is
nasty: `/v1/models` happily advertises `whisper-base-en-q5_1`, so every readiness check
passes, and the request then fails with `backend not found: whisper`. The stack installs the
backend on start if absent, into a volume, so it downloads once.

Two ceilings that are not decoration. LocalAI's default **upload limit is 15 MB** while 16 kHz
mono audio runs ~115 MB per hour, so a real meeting is refused mid-upload and surfaces only as
a broken pipe (a 278 MB recording, 2026-09-01). And whisper decodes audio to float32 —
**measured peak 2,270 MB** for one hour — so the 2 GB limit was OOM-killed with nothing but
`error reading from server: EOF`; 4 GB covers the two-hour planning ceiling.

## The vocabulary prompt, and why it needs a proxy

Whisper accepts a prompt that biases decoding toward expected words. It is the difference
between "Chata Nougah" and "Chattanooga", measured A/B on identical audio 2026-08-29.

It cannot be set where it belongs. LocalAI reads the prompt from the **request only**
(`prompt := c.FormValue`, with no model-config fallback, unlike `language` and `translate`),
and `integration_openai` has no setting that sends one. So `stt-prompt-proxy` sits between
them and splices one extra multipart part onto the front of the body — it does not parse and
rebuild the body, so it cannot corrupt the audio payload.

## HPB_PATH must be empty

`talk-recording`'s `HPB_PATH` must be **empty**, not the image's `/standalone-signaling/`
default.

The recorder looks its signaling secret up by **exact string match** on the URL Nextcloud
reports (`Config.getSignalingSecret`: `signalingUrl.rstrip('/')` then `in self._signalings`).
Our `spreed` `signaling_servers` is the bare host, because the HPB has its own hostname; AIO
instead puts signaling on a path of the main domain, which is where that default comes from.
Left at the default the stored key is `.../standalone-signaling`, the lookup misses, there is
no `[signaling] internalsecret` to fall back to, and every recording dies with "No configured
signaling secret" **after the call has already started** (measured on production 2026-08-30).

## Changing a script means bumping its config name

Every script this stack ships — `init.sh`, `taskworker.sh`, `recording-share.sh`,
`stt-prompt-proxy.py`, `share-recordings.php` — reaches its container as a Swarm
**config**, and Swarm configs are **immutable**. Editing the file changes nothing on its
own: the name is the identity, so a redeploy that finds an existing config under the
same name keeps the **old** content and reports success.

So a script change is two edits, not one:

1. the file, and
2. `name:` for its config in `docker-compose.yml` — **and every stack environment that
   overrides that name**.

Missing the second half is silent in the direction that matters. The deploy goes green
and the container runs the previous script.

**Names are cluster-scoped, not stack-scoped.** Three Nextcloud stacks share the
production Swarm, so the defaults here (`nextcloud_*`) would be shared between them if
two stacks ever took the default at once. Production therefore pins its own prefix —
`cdcloud_init_14`, `cdcloud_stt_proxy_4`, `cdcloud_share_recordings_2` — and any new
config added to this stack should be pinned the same way rather than left on the
default.

### Checking a pin before you deploy

Compare what the Swarm holds under the pinned name against the file in the repo. Equal
hashes mean the redeploy is a no-op for that script; different hashes mean the pin is
stale and must be bumped in the stack environment first.

```sh
# for one config: <pinned name> vs <repo file>
curl -fsS "$PORTAINER/api/endpoints/$EP/docker/configs" -H "Authorization: Bearer $JWT" \
  | jq -r --arg n "$NAME" '.[] | select(.Spec.Name==$n) | .Spec.Data' \
  | base64 -d | sha256sum
sha256sum stacks/nextcloud/scripts/init.sh
```

**Measured on production 2026-09-10:** `cdcloud_init_14` holds content that no longer
matches `scripts/init.sh`, while `cdcloud_stt_proxy_4` and `cdcloud_share_recordings_2`
both match. `taskworker.sh` and `recording-share.sh` are new and exist under no name
yet. So whoever deploys this branch to production sets, in the stack environment:

| variable | set to | why |
|---|---|---|
| `INIT_CONFIG_NAME` | `cdcloud_init_15` | current pin is stale |
| `TASKWORKER_CONFIG_NAME` | `cdcloud_taskworker_1` | new; keep off the shared default |
| `RECORDING_SHARE_SH_CONFIG_NAME` | `cdcloud_recording_share_sh_1` | new; same reason |
| `STT_PROXY_ENTRYPOINT_CONFIG_NAME` | `cdcloud_stt_proxy_entrypoint_1` | new; same reason |

Set `ADMIN_EMAIL` at the same time. The shared service admin (`ADMIN_USER`) is created with
no address, so it cannot be sent a password reset and receives no administrator alerts — the
account with the most privilege on the instance and the least way back into it. `init.sh` now
sets it on every run rather than only at creation, because the account already exists
everywhere and the create branch deliberately leaves existing accounts alone.

A git-backed stack cannot take an environment-only update, so the bump and the redeploy
are one action, not two.

### The same redeploy should correct `TRUSTED_PROXIES`

Production's value is **comma-separated**: 39 characters holding three CIDRs and no
spaces, re-measured 2026-09-10. The image builds the array with
`explode(' ', $tp)`, so that is one entry matching no proxy, and proxy trust is simply
off — `REMOTE_ADDR` is Traefik for every request, which is what rate limiting,
brute-force protection and every logged client IP are keyed on.

Re-separating the same three CIDRs with spaces fixes it. Nothing else changes, and it
costs nothing extra because a git-backed stack has to be redeployed to take the config
names above anyway.

To check the shape without printing the value:

```sh
curl -fsS "$PORTAINER/api/stacks/99" -H "Authorization: Bearer $JWT" \
  | jq -r '.Env[] | select(.name=="TRUSTED_PROXIES") | .value' \
  | grep -qa ',' && echo 'comma-separated: proxy trust is OFF'
```
