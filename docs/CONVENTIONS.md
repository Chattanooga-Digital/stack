# Stack conventions

Rules a new stack directory follows. Most of these exist because something bit us
once. [stacks/bigcapital](../stacks/bigcapital) is the reference implementation.

## Layout

Every stack is `stacks/<name>/` holding:

- `docker-compose.yml`
- `.env.example` with a REQUIRED block and a commented OPTIONAL block
- `README.md` covering **only what is true of this stack and not the others**
- `scripts/` only if a service runs shell longer than a few lines, which never
  lives inline in `command:`

A stack README does not restate the platform baseline, the Portainer deploy
procedure, or anything on this page. Assume the reader has read both. Write down
what the next person would get wrong: upstream deviations, routing that isn't
obvious, values that look required but aren't, migration steps.

## Platform baseline

Every stack assumes all of this and none of them document it again:

- Docker Swarm, services pinned to manager nodes
- Traefik v3 with a `websecure` entrypoint and a `le` cert resolver, on the
  external overlay `traefik_net`
- The external overlay `internal_network`, for stacks that talk to something
  outside themselves
- DNS for the instance's domain pointing at the node
- Deployed by Portainer per [the root README](../README.md#adding-a-stack)

A stack that needs something beyond this list says so. Mastodon's external
`postgres_db` is the current example.

## Nothing instance-specific in the compose file

The compose file should deploy unchanged as many times as you like, once per
Portainer stack, with a different environment each time. Anything that differs
between instances is a variable: domain, SMTP, buckets, credentials, image tags,
memory limits.

Required variables use `${VAR:?VAR not set}` so a missing one fails the deploy by
name instead of producing a half-working container. Optional variables use
`${VAR:-default}` and can be left out entirely.

## INSTANCE_NAME namespaces Traefik

Traefik router, service, and middleware names are **global across every stack on
the same Traefik**. Two deployments sharing a name silently fight over the same
router and one wins non-deterministically.

So every Traefik object name is built from `INSTANCE_NAME`, and each instance gets
a distinct value. Volumes and networks do not need this: declare them unprefixed
and Swarm namespaces them with the stack name, so `bigcapital_db` becomes
`<stack>_bigcapital_db`.

Variable names are unprefixed. Where a container demands a specific name, that
is the key, not the variable: nextcloud's talk service reads `NC_DOMAIN`, fed
from `${DOMAIN}`.

## Swarm wiring

- `traefik_net` and `internal_network` are external overlays, never declared here
- Services needing ingress join `traefik_net`, everything else stays internal
- A stack whose services only talk to each other declares its own overlay instead
  of joining `internal_network`, as bigcapital does. Join the shared one only to
  reach another stack, as mastodon does for `postgres_db`
- Traefik labels go under `deploy.labels`, not `labels`, and use
  `traefik.swarm.network=traefik_net`
- Pin services to managers with `placement.constraints: [node.role == manager]`
- Stateful services update `stop-first`, stateless update `start-first`

## Scripts

A stack script reaches its container as a Swarm `config` sourced from the repo
checkout, so the deployed ref's script is what runs. Never fetch code from the
network at deploy time. Config objects are immutable: version the config name
when the file changes, or the redeploy fails.

## Credentials

Credentials are environment variables, set in Portainer's stack environment
panel. No stack uses Swarm secrets. They are readable from `docker service
inspect` by anyone who can already reach the Swarm, and the `*_FILE` indirection
that avoids that costs a shell wrapper on every service and an out-of-band
`docker secret create` step per credential that Portainer will not do for you.
Mastodon ran that way once; it was not worth the friction.

Keep passwords and secrets **alphanumeric**. Portainer's UI mangles percent,
asterisk, and dollar characters in env values.

## Two dollar-sign traps

A bare `$` anywhere in the file, including inside a comment, makes Portainer's
stack-create API return 500. Escape every literal dollar as `$$`, which is also
how you pass one through to a container without compose interpolating it.

## Pin versions

Never float a major tag on a stateful service. Nextcloud refuses a database
written by a newer version and will not skip a major, so `nextcloud:apache`
resolving to a new release is a broken instance, not an upgrade.

## Anchors do not cross files

`docker stack deploy` resolves YAML anchors within a single file and does not
support `extends` or `include`. The `x-deploy-defaults` and `x-healthcheck-defaults`
boilerplate is copied into each stack on purpose. The monorepo makes the drift
greppable, not absent.

## Secrets never land in git

`.env` is gitignored. Real values live in Portainer's stack environment panel.
`.env.example` is the tracked contract, and CI fails if a required variable is
missing from it.
