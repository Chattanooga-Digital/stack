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
