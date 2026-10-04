# Authentik

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## Forced password change

authentik has no per-user must-change flag. `blueprints/force-password-reset.yaml`
implements the vendor's substitute. Set the user attribute `reset_password` and the
person is prompted at next login; the flag clears once they have changed it.

```
PATCH /api/v3/core/users/<pk>/   {"attributes": {"reset_password": true}}
```

## Set-password links

The blueprint adds a recovery flow with two entry points:

| Route | Started by | Needs mail |
|---|---|---|
| `POST /api/v3/core/users/<pk>/recovery/` | an admin, returns the link | no |
| the login page's recovery link | the person | yes |
