# Bigcapital

[Bigcapital](https://github.com/bigcapitalhq/bigcapital), accounting. The
reference implementation for [the conventions](../../docs/CONVENTIONS.md).

Differs from upstream's `docker-compose.prod.yml`: the bundled Envoy proxy is
dropped because Traefik handles ingress and TLS, and the locally-built migration
image is replaced by a one-shot service running the same CLI out of the published
server image.

## Migrations

The `migration` service is one-shot: it waits for the database, runs system and
tenant migrations, exits, and stays down (`restart_policy: condition: none`).
It runs on every stack deploy.

After changing `BIGCAPITAL_VERSION`, re-run it:

```
docker service update --force <stack>_migration
docker service logs <stack>_migration
```

## Routing

Two routers per instance on the same hostname, separated by priority:

| Router | Rule | Priority | Port |
|---|---|---|---|
| `${INSTANCE_NAME}-api` | `Host(...) && PathPrefix(/api)` | 20 | 3000 |
| `${INSTANCE_NAME}-web` | `Host(...)` | 10 | 80 |

The `/api` prefix is passed through unstripped. Priorities are explicit so routing
doesn't depend on Traefik's default rule-length ordering.

## Notes

- `BIGCAPITAL_VERSION` must exist for both images. `server` and `webapp` are a matched
  pair driven by one variable, and the tags are not always in lockstep. A tag present
  for only one fails the deploy.
- `DB_USER` is `root`. Each stack has its own MariaDB, so root avoids a grant script
  for the per-tenant databases Bigcapital creates at runtime.
- `depends_on` is ignored by Swarm. Startup ordering comes from
  `restart_policy: condition: any` (services crash-loop until dependencies answer)
  and from the migration service's own wait loop.
- No healthcheck on `server` or `webapp`. Their images haven't been verified to carry
  `curl` or `wget`, and a healthcheck whose binary is missing marks the service
  unhealthy and restart-loops it. Add one once the image contents are confirmed.
- This stack runs its own `bigcapital_internal` overlay rather than joining the
  shared `internal_network`. Nothing outside the stack talks to its database.
