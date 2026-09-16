# Authentik

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## What is not obvious

**It needs four containers, not two.** The `worker` is not optional: database
migrations, outpost management and every scheduled task run there. With the server
alone, Authentik starts, serves a login page, and never completes setup. This is the
most expensive candidate on the shortlist for that reason.

**`server` and `worker` share one environment block** (a YAML anchor) and must run the
same image tag. If they diverge across an upgrade, migrations run against the wrong
schema.

**`SECRET_KEY` signs sessions and tokens.** Changing it invalidates every existing
session and every issued token. It is not a rotatable credential in the ordinary sense.

**Bootstrap variables seed an EMPTY database only.** `AUTHENTIK_BOOTSTRAP_EMAIL` and
`AUTHENTIK_BOOTSTRAP_PASSWORD` are read once, on a database with no users.
