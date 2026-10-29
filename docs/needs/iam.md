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
- UX built around self-service for the org, the lower skill threshold the better

## Candidates

- [Keycloak](../portfolio/keycloak.md)
- Authentik
- Zitadel
- Open Identity Platform

## Evaluation

Put your initials and the date in a cell once you've checked it yourself, same
rule as the [validation checkboxes](../PORTFOLIO.md#validation-checkboxes). An
empty cell means nobody has.

| Requirement | Keycloak | Authentik | Zitadel | Open Identity Platform |
|---|---|---|---|---|
| OIDC | | | | |
| SAML | | | | |
| MFA: TOTP and passkeys | | | | |
| Self-service password reset, profile edit | | | | |
| Group claims to apps, so app groups come from the IdP | | | | |
| Disabling a user in the IdP locks them out of every app | | | | |
| No feature above gated behind a paid tier | | | | |
| Target SSO coverage across the portfolio | | | | |
| **Nice to have** | | | | |
| Multi-tenancy | | | | |
| LDAP server, for apps that only do LDAP | | | | |
| Forward auth through Traefik, for apps with no SSO at all | | | | |
| UX built around self-service for the org, the lower skill threshold the better | | | | |
| **Also** | | | | |
| Licence | | | | |
| Could we fix it ourselves | | | | |

## Notes

---

SSO coverage is a huge question here, most FOSS **DOES NOT SUPPORT SSO** and the cost to add it can easily be thousands of dollars per project (not accounting for additional support overhead if we have to fork it to do so). We probably need some sort of target coverage for success/failure here or it isn't worth our time. - William Roush 2026-08-10

---

LDAP, from William's hands-on testing on another deployment (devops list, 2026-10-18), in his words: Authentik's "LDAP sync" works poorly, and "the UI in general is kind of a struggle bus and really poor error messaging". Keycloak "doesn't run its own LDAP server internally, can just hook into one". And "Chattanooga Digital didn't really have a strong reliance on LDAP", which fits the LDAP server row sitting under Nice to have. Sync (pulling users in from another directory) is not the same as that row (serving LDAP to apps). His fuller report is to follow. - Jon Pohlner 2026-10-18
