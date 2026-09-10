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
