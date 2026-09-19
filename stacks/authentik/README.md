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

## Forcing a password change: no per-user flag, so it takes a flow

Keycloak takes `temporary: true` when you set a password and Zitadel takes
`changeRequired: true` — one field, per user. **authentik has no equivalent**, and
nothing errors to tell you so: the password is simply set and the account works. An
earlier version of this file stopped there and called it impossible. It is not.

The vendor documents the substitute:
[Force password reset on next login](https://docs.goauthentik.io/users-sources/user/password_reset_on_login/)
— two expression policies, a prompt stage, a user-write stage, and bindings that place
them in the authentication flow. `blueprints/force-password-reset.yaml` in this stack
does exactly that, applied declaratively rather than clicked into the console.

**To make a person set a new password at their next login**, give them the user
attribute `reset_password: true`:

```
PATCH /api/v3/core/users/<pk>/   {"attributes": {"reset_password": true}}
```

The second policy clears the flag once they have done it.

### Four things that will cost you an hour each

**The orders must sit between the password stage and MFA.** On this instance the live
bindings are identification `10`, password `20`, mfa-validation `30`, login `100`, so
the blueprint uses `25` and `26`. Read the live orders before trusting those numbers.

**`evaluate_on_plan` must be false and `re_evaluate_policies` true.** The policies read
`request.context["pending_user"]`, which does not exist when the flow is *planned* —
only once the identification stage has run. Evaluate on plan and it raises, and the
stage is skipped without a word.

**The validation policy is `default-password-change-password-policy`.** The vendor page
abbreviates it to `default-password-change-policy`, which does not exist here.

**Never set `reset_password` from the blueprint.** Blueprints re-apply on every
discovery, so a baked-in `true` would restore the flag right after someone cleared it
and that person could never finish logging in. It is per-person state; it belongs on
the API.

### Mail, and the trap that hid it

`AUTHENTIK_EMAIL__*` is read from the stack environment at runtime, so unlike Zitadel's
instance settings it does take effect on a redeploy. **This stack was deployed with
`SMTP_HOST=smtp.invalid`** — a placeholder that satisfies the compose's `${SMTP_HOST:?}`
requirement while guaranteeing nothing is ever sent, and nothing errors to say so.

With a real relay set, the blueprint's recovery flow gives two independent routes in:

| route | who starts it | needs mail |
|---|---|---|
| `POST /api/v3/core/users/<pk>/recovery/` | an admin; **returns** the link to carry | no |
| the login page's recovery link | the person themselves | yes |

The first is why links were possible here long before mail was. `recovery_email/` is the
one that sends, and it additionally requires an `email_stage` argument — it returns
`400 {"email_stage":["This field is required."]}` without one.

The self-service route needs the identification and email stages to be **skipped** when
the flow was entered through a minted link, or a person who is already identified gets
asked who they are. That is what `chattanooga-recovery-only-if-self-started` does, reading
`request.context["is_restored"]`.

### How the file reaches the container

authentik applies any blueprint YAML under `/blueprints`, and the **worker** is what
applies them. The file ships as a Swarm `config` sourced from the repo checkout, the
same way `stacks/nextcloud` ships its scripts, mounted on **both** `server` and
`worker` — the `&authentik-env` anchor covers `environment:` only, so `configs:` has to
be written out on each service separately.

🔴 **Swarm configs are immutable.** Bump `BLUEPRINT_CONFIG_NAME` in the same commit as
any edit to the blueprint, or the redeploy reports success while the old content keeps
running.

Verify it *applied* rather than merely mounted by reading the policies and stages back
over the API. A file that was never discovered looks identical from the compose side.

## Accounts: invite links, not passwords we choose

Only ONE credential for this stack is ours to hold: the bootstrap admin, which exists
to configure the system and nothing else. Real people are added by creating the
account and letting the system send them a set-password link. We never learn their
password, so there is nothing for us to store, leak, or be asked to rotate.

That makes SMTP load-bearing rather than a nicety, which is why the mail variables are
required here and have no defaults. An invitation that cannot be sent does not error —
it just never arrives, and the symptom is a person saying they got no email.
