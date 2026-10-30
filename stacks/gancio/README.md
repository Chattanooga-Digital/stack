# gancio

Shared agenda for local communities. ActivityPub, RSS, iCal.

Gancio reads `/config.json` and serves a first-run setup wizard when it is
absent. `scripts/entrypoint.sh` renders the file from the stack environment on
every start, then runs migrations.

Mail is configured in Administration > Settings. Gancio takes no SMTP
variables, so a deploy onto empty volumes starts with mail off and password
resets and submission confirmations fail silently.

The stack pins 1.x. Upstream's docs recommend the `beta` tag, which is 2.x, and a
2.x schema will not roll back.

Gancio enables `trust proxy` unconditionally (`server/routes.js`), so its rate
limiter keys on a client-supplied `X-Forwarded-For`. Anonymous event submission
is on by default; have Traefik overwrite the header before opening the instance
to the public.
