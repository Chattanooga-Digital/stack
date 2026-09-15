# IAM

[Needs index](../NEEDS.md)

| | |
|---|---|
| Status | Open |
| Decision | |

## Requirements

- OIDC
- SAML
- MFA: TOTP and passkeys
- Self-service password reset, profile edit
- Group claims to apps, so app groups come from the IdP
- Disabling a user in the IdP locks them out of every app
- No feature above gated behind a paid tier
- Target SSO coverage across the portfolio

## Nice to have

- Multi-tenancy. Fallback is one deployment per tenant
- LDAP server, for apps that only do LDAP
- Forward auth through Traefik, for apps with no SSO at all

## Candidates

- [Keycloak](../portfolio/keycloak.md)
- Authentik
- Zitadel
- Open Identity Platform

## Notes

---

SSO coverage is a huge question here, most FOSS **DOES NOT SUPPORT SSO** and the cost to add it can easily be thousands of dollars per project (not accounting for additional support overhead if we have to fork it to do so). We probably need some sort of target coverage for success/failure here or it isn't worth our time. - William Roush 2026-08-10
