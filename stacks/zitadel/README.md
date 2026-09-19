# Zitadel

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## What is not obvious

**`MASTERKEY` must be exactly 32 characters.** Not "at least" — exactly. Zitadel
refuses to start on any other length. It encrypts every stored secret, so it cannot be
rotated later without re-encrypting the instance.

**Traefik must speak h2c to it.** Zitadel's management API is gRPC-Web, so the service
carries `loadbalancer.server.scheme=h2c`. Without it the console loads and every API
call fails, which looks like a permissions problem and is not.

**`start-from-init` runs setup and then serves**, so a fresh volume needs no separate
init step. On an existing database it is a no-op, so it is safe to leave in place.

**`ZITADEL_EXTERNALSECURE=true` with `--tlsMode external`** is the combination for
running behind a TLS-terminating proxy. Setting one without the other produces
redirect loops.

**No `_FILE` secret support.** Every credential is a plain environment variable, which
is the same constraint the rest of this repo already works under, but worth knowing if
that changes.

## Signing in as the seeded admin, which is where an hour goes

**The login name is not `admin`.** Zitadel qualifies it with the org domain, so it is
`<ADMIN_USER>@<ORG_NAME>.<DOMAIN>` — by default `admin@zitadel.<your domain>`. A bare
`admin` does resolve, passes the login-name step, and is then rejected at the password
step with **`Errors.User.NotHuman`**, which reads like the account was never created as
a person. It was; you addressed the wrong one.

**The seeded admin is asked to change its password at first login** unless
`ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORDCHANGEREQUIRED` is `false`. Letting that
happen means `ADMIN_PASSWORD` in the stack environment no longer describes a password
that works, so the stack file stops being the truth about the system and the real
credential lives only in whoever typed it. This compose seeds it already-changed for
that reason.

That is a trade rather than a free win, and worth naming as one: turning the flag off
removes a layer. What still protects the account is that the password is
machine-generated and long, not that it gets replaced on first use. It is acceptable
here because this is a bootstrap admin on an evaluation stack holding nothing.
**If Zitadel is the candidate we choose, set it back to `true`** and record the
changed password properly before any real account or data arrives.

**A 2-factor enrolment prompt follows the password.** It is a prompt and not a policy —
the page carries a skip — but an automated sign-in that does not expect it simply stops
on an HTML page with no error in it.

Both of the above apply on an EMPTY database only. Changing them later needs a fresh
deploy, not a redeploy.

## Accounts: invite links, not passwords we choose

Only ONE credential for this stack is ours to hold: the bootstrap admin, which exists
to configure the system and nothing else. Real people are added by creating the
account and letting the system send them a set-password link. We never learn their
password, so there is nothing for us to store, leak, or be asked to rotate.

That makes SMTP load-bearing rather than a nicety, which is why the mail variables are
required here and have no defaults. An invitation that cannot be sent does not error —
it just never arrives, and the symptom is a person saying they got no email.
