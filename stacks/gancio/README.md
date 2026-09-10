# gancio

A shared agenda for local communities. Publishes events over ActivityPub, RSS,
iCal and embeddable widgets.

## It is configured by a JSON file, not by environment variables

This is the thing to know before changing anything. `server/config.js` reads
`-c/--config`, defaulting to `/config.json`. When that file does not exist it
does not fail: it sets `status: SETUP` and serves a first-run wizard. A stack
that mounted no config would come up, pass a health check and show a setup
screen to the public.

So `scripts/entrypoint.sh` renders `/config.json` from the stack environment on
every start, then runs `cli.js migrate` before `cli.js start`. The compose file
stays instance-agnostic and Portainer's environment panel remains the only place
instance values live.

The script reaches the container as a Swarm config, which is immutable. Editing
it means bumping `ENTRYPOINT_VERSION`, or the redeploy fails on a name that
already exists.

## Version choice: stable 1.x, not the tag upstream recommends

`gancio.org/install/docker` says `cisti/gancio:beta`. That tag currently resolves
to `2.0.0-beta.5`, and `beta` moves. Two reasons this stack pins 1.28.2 instead:

Under Swarm a floating tag is not floating. The tag is resolved to a digest when
the service is created and never re-resolved, so `beta` pins itself to whatever
was current on the day of deploy while continuing to read as self-updating. The
only way to know what is running is to compare the running digest against what
the registry resolves the tag to now.

And 2.0.0-beta.5 is beta software holding event data. Moving up is one variable:
set `GANCIO_VERSION=2.0.0-beta.5` and redeploy. Read upstream's changelog first,
because a major that has written its schema will not roll back.

## Paths are absolute on purpose

`config.example.json` uses paths relative to the working directory. This stack
writes absolute ones under `/data`. A working-directory change upstream would
otherwise relocate uploads onto the container filesystem, where they survive
until the next redeploy and then do not.

## Database

Postgres. The image bundles `pg`, `mariadb` and `sqlite3` drivers, and upstream's
example uses sqlite. Sqlite on a Swarm volume works but gives no way to take a
consistent dump while the service runs, so this uses postgres for the same
reason the other stacks do.

The entrypoint waits by asking the database a question rather than checking the
port, because postgres accepts TCP before it accepts queries and the first
migration otherwise races the socket.

## Anonymous event submission is on by default

Upstream ships it that way deliberately, and it is the feature the project is
built around rather than an oversight. Decide whether you want it before pointing
anyone at the instance: Admin, then Settings.

## Its rate limiting can be bypassed, and that is upstream

On every start gancio logs an Express error worth reading rather than filtering:

> The Express 'trust proxy' setting is true, which allows anyone to trivially
> bypass IP-based rate limiting.

`server/routes.js:28` calls `app.enable('trust proxy')` unconditionally. There is
no configuration key for it, so this is a property of the software and not
something the stack got wrong. Trusting every hop means the rate limiter keys on
a header the client can set, so `server/api/limiter.js` protects nobody who
chooses to send their own `X-Forwarded-For`.

That matters more here than it would elsewhere, because anonymous event
submission is enabled by default. Anyone deciding to open this instance to the
public should assume submission rate limiting is not enforced, and consider
having Traefik overwrite the incoming header rather than append to it.

Reproduced on 1.28.2. Worth re-checking on 2.x before that upgrade.
