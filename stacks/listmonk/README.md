# listmonk

[listmonk](https://listmonk.app), a self-hosted newsletter manager. It sends nothing
itself: each message goes to the SMTP relay in `SMTP_HOST`, which is what gets mail
into inboxes.

## Settings live in the database

listmonk keeps its settings (root URL, sender, SMTP, bounce handling) in Postgres,
not in the environment. The one-shot `configure` service writes the per-instance ones
through listmonk's API on every deploy, and is safe to re-run:

```
docker service update --force <stack>_configure
docker service logs <stack>_configure
```

It also removes the sample subscribers, lists and campaign the installer seeds, and
leaves the public subscribe page off.

## Upgrade

Changing `LISTMONK_VERSION` is the whole procedure; the `app` command applies pending
upgrades before serving. Dump the database first.

## Backup

Subscribers, lists, campaigns, templates and settings are all in `listmonk_db`;
`listmonk_uploads` holds only images uploaded into campaigns.

```
pg_dump -U listmonk listmonk
```

run inside the `db` container.

## Bounces

Bounces need the provider to call back. For SendGrid, set `SENDGRID_WEBHOOK_KEY` and
point its Event Webhook at `https://<LISTMONK_DOMAIN>/webhooks/service/sendgrid`.

`SMTP_PASSWORD` is stored in the database by `configure`, so rotating it means changing
the variable and re-running `configure`.
