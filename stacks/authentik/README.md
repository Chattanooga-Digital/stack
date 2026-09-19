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

## There is no per-user "must change this password"

Measured 2026-09-18. Keycloak takes `temporary: true` when you set a password and
Zitadel takes `changeRequired: true` — one field, per user, and the person is stopped
at a change-password screen on first sign-in. Authentik has no equivalent.

What it has instead is a **password-expiry policy measured in days**
(`/api/v3/policies/password_expiry/`, none configured here) bound into the
authentication flow, which routes a user to `default-password-change` once their
`password_change_date` is old enough. That is an age rule, not a
this-password-was-issued-to-you rule, and it does not express "new account, must be
changed before first use".

`password_change_date` is on the user object but is a record of when it last changed,
not a control.

Consequence for provisioning: a password set here is simply the person's password
until they choose to change it. If that matters, say so in the message that carries it.

## Accounts: invite links, not passwords we choose

Only ONE credential for this stack is ours to hold: the bootstrap admin, which exists
to configure the system and nothing else. Real people are added by creating the
account and letting the system send them a set-password link. We never learn their
password, so there is nothing for us to store, leak, or be asked to rotate.

That makes SMTP load-bearing rather than a nicety, which is why the mail variables are
required here and have no defaults. An invitation that cannot be sent does not error —
it just never arrives, and the symptom is a person saying they got no email.
