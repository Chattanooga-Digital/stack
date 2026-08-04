# Mastodon

[Mastodon](https://github.com/mastodon/mastodon), running `toot.chattanooga.digital`.

Five services: `web` (Puma), `streaming`, `sidekiq`, plus a dedicated `redis` and
a single-node `es` for full-text search.

## Needs a PostgreSQL it does not own

Beyond the [platform baseline](../../docs/CONVENTIONS.md#platform-baseline),
this stack needs a reachable `postgres_db` on `internal_network` with a database
and role matching `DB_NAME` and `DB_USER`. That database lives in another stack.
Nothing here creates or backs it up.

## Credentials

`SECRET_KEY_BASE`, `OTP_SECRET`, and the three `ACTIVE_RECORD_ENCRYPTION_*`
values are not rotatable in practice: changing them invalidates sessions and
makes existing encrypted columns unreadable.

`VAPID_PUBLIC_KEY` is public by design. Both halves are base64url and break the
alphanumeric rule the other stacks follow, so paste them exactly.

### Migrating an existing instance

This stack used to read nine external Swarm secrets. Read each one out and paste
it into the matching variable:

| Old secret | Variable |
|---|---|
| `mastodon_secret_key_base` | `SECRET_KEY_BASE` |
| `mastodon_otp_secret` | `OTP_SECRET` |
| `mastodon_active_record_encryption_deterministic_key` | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` |
| `mastodon_active_record_encryption_key_deriviation_salt` | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` |
| `mastodon_active_record_encryption_primary_key` | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` |
| `mastodon_vapid_private_key` | `VAPID_PRIVATE_KEY` |
| `mastodon_db_pass` | `DB_PASSWORD` |
| `mastodon_secret_access_key` | `S3_SECRET_ACCESS_KEY` |
| `mastodon_es_pass` | `ES_PASS`, optional and ignored |

`VAPID_PUBLIC_KEY` was hardcoded in the compose file as
`BFuleNB9StytQ9oYZmF23xtgs4ZqZ3ehcieMxtbRAlFpPnlRyaVrEqSauHSWR2iykgIIWCdo_4fiza-kHD4461w=`.

Once the stack redeploys clean, `docker secret rm` on all nine is safe.

## Notes

- Changing `MASTODON_DOMAIN` on a live instance breaks federation. It is not a
  rename knob.
- `redis`, `es`, and `sidekiq` update stop-first and drop briefly on every
  deploy. `web` and `streaming` update start-first.
- `es` runs with `xpack.security.enabled=false`, but the services still pass
  `ES_USER` and `ES_PASS`. They are ignored, which is why `ES_PASS` is optional
  and empty. Don't read it as evidence that search auth is on.
