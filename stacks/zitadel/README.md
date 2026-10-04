# Zitadel

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

The seeded admin signs in as `<ADMIN_USER>@<ORG_NAME>.<DOMAIN>`. The bare
username passes the login-name step and fails at the password step with
`Errors.User.NotHuman`.

SMTP is required. Zitadel invites users by email, and an unsent invitation
raises no error.

Instance settings (`ORG_NAME`, `ADMIN_*`, `SMTP_*`) apply to an empty database
only. Changing them needs a fresh deploy.
