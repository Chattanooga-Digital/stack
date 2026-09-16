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

## Accounts: invite links, not passwords we choose

Only ONE credential for this stack is ours to hold: the bootstrap admin, which exists
to configure the system and nothing else. Real people are added by creating the
account and letting the system send them a set-password link. We never learn their
password, so there is nothing for us to store, leak, or be asked to rotate.

That makes SMTP load-bearing rather than a nicety, which is why the mail variables are
required here and have no defaults. An invitation that cannot be sent does not error —
it just never arrives, and the symptom is a person saying they got no email.
