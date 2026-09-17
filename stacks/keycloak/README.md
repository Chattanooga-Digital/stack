# Keycloak

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## What is not obvious

**The admin variables were renamed in 26.x.** `KEYCLOAK_ADMIN` and
`KEYCLOAK_ADMIN_PASSWORD` are gone; it is now `KC_BOOTSTRAP_ADMIN_USERNAME` and
`KC_BOOTSTRAP_ADMIN_PASSWORD`. The old names are silently ignored, so the stack comes
up with no admin and no error.

**They seed an EMPTY database only.** Changing `ADMIN_PASSWORD` after first boot does
nothing. Use the console, or start from an empty volume.

**The heap is capped on purpose.** Left alone the JVM sizes itself against the *host's*
RAM rather than the container limit, which on a shared node means it will happily grow
past whatever ceiling Swarm declares. `JAVA_OPTS_KC_HEAP` must stay well under
`MEM_LIMIT_KEYCLOAK`.

**`start --optimized` skips the build step**, so a config change that needs a rebuild
(a new feature flag, a different DB vendor) will not take effect. Drop `--optimized`
for those, accept a slower start.

`KC_PROXY_HEADERS=xforwarded` is required because Traefik terminates TLS; without it
Keycloak issues redirects to `http://` and login loops.

## Accounts: invite links, not passwords we choose

Only ONE credential for this stack is ours to hold: the bootstrap admin in
`ADMIN_PASSWORD`, which exists to configure the system and nothing else. Real people
are added by creating the account and letting the system send them a set-password
link. We never learn their password, so there is nothing for us to store, leak, or be
asked to rotate.

**Mail is configured in the application, not here.** Unlike Authentik and Zitadel,
this one takes no SMTP environment variables — it is set in the admin console after
first boot. That is a manual step, and until it is done every invitation and every
password reset **fails silently**. Gancio sat in exactly that state from 4 September
with nobody noticing, so check it deliberately rather than assuming.
