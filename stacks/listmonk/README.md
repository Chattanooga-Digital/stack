# listmonk

[listmonk](https://listmonk.app), a self-hosted newsletter manager. It sends nothing
itself: each message goes to the SMTP relay set in the admin UI, which is what gets
mail into inboxes.

## First login

listmonk keeps its settings in Postgres, so they are set once in the admin UI at
`https://<LISTMONK_DOMAIN>/admin`, signed in as `ADMIN_USER`. Do this right after the
first deploy: the public subscription page starts on.

Under Settings:

- General: turn off Enable public subscription page. Set Root URL to
  `https://<LISTMONK_DOMAIN>` and Default `from` email to an address verified at the
  SMTP provider.
- SMTP: for SendGrid, `smtp.sendgrid.net`, user `apikey`, password a Mail Send key.
- Performance: keep Message rate under the provider's limit.

Then delete the sample subscribers, lists and campaign the installer seeds.

## Upgrade

Changing `LISTMONK_VERSION` is the whole procedure; the `app` command applies pending
upgrades before serving. Dump the database first.

## Backup

Subscribers, lists, campaigns, templates and settings, SMTP password included, are all
in `listmonk_db`; `listmonk_uploads` holds only images uploaded into campaigns.

```
pg_dump -U listmonk listmonk
```

run inside the `db` container.

## Bounces

Bounces need the provider to call back. For SendGrid, turn on Enable bounce processing,
Enable bounce webhooks and Enable SendGrid under Settings, Bounces. Paste the signed
Event Webhook's verification key into SendGrid Key, and point the webhook at
`https://<LISTMONK_DOMAIN>/webhooks/service/sendgrid`.
