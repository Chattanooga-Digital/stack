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
| OIDC | Yes, SSO into Nextcloud and Drupal (Claude 2026-11-06) | Yes, SSO into Nextcloud and Drupal (Claude 2026-11-06) | Yes, SSO into Nextcloud and Drupal (Claude 2026-11-06) | Yes, SSO into Nextcloud and Drupal (Claude 2026-11-06) |
| SAML | Realm descriptor served; no app tested (Claude 2026-11-06) | SAML provider present; no app tested (Claude 2026-11-06) | SAML IdP present; no app tested (Claude 2026-11-06) | SAML federation present; no app tested (Claude 2026-11-06) |
| MFA: TOTP and passkeys |  | TOTP and WebAuthn stages present; not exercised (Claude 2026-11-06) | TOTP and passkey factors present; setup prompt at first login, skippable (Claude 2026-11-06) | MFA modules present; passkeys not checked (Claude 2026-11-06) |
| Self-service password reset, profile edit |  |  | In the login UI (Claude 2026-11-06) |  |
| Group claims to apps, so app groups come from the IdP | Yes, with a groups mapper on the client; Nextcloud showed the group (Claude 2026-11-06) | Yes, default profile scope; Nextcloud showed the group (Claude 2026-11-06) | Needs an Action that flattens roles into a groups array; then Nextcloud showed the group (Claude 2026-11-06) | No out of the box; needs a claims script edit, not tried (Claude 2026-11-06) |
| Disabling a user in the IdP locks them out of every app | New logins refused; existing app sessions stay until they expire (Claude 2026-11-06) | New logins refused; existing app sessions stay until they expire (Claude 2026-11-06) | Login refused at the login name step; reactivating restored it; existing sessions not checked (Claude 2026-11-06) | New logins refused; reactivating restored it; existing sessions not checked (Claude 2026-11-06) |
| No feature above gated behind a paid tier |  | None of the rows above sit in the enterprise directory (paid-use licence: RADIUS, SCIM, SSF, WS-Federation, Google and Entra provisioning, account lockdown, mTLS, unique password policy) (Claude 2026-11-06) |  |  |
| Target SSO coverage across the portfolio | Nextcloud and Drupal only; rest not tested (Claude 2026-11-06) | Nextcloud and Drupal only; rest not tested (Claude 2026-11-06) | Nextcloud and Drupal only; rest not tested (Claude 2026-11-06) | Nextcloud and Drupal only; rest not tested (Claude 2026-11-06) |
| **Nice to have** | | | | |
| Multi-tenancy | Realms; one created in the test (Claude 2026-11-06) | Tenants and brands present (Claude 2026-11-06) | Organisations present (Claude 2026-11-06) |  |
| LDAP server, for apps that only do LDAP |  | LDAP provider present; needs an outpost container (Claude 2026-11-06) |  | Users live in OpenDJ, an LDAP server that ships with it (Claude 2026-11-06) |
| Forward auth through Traefik, for apps with no SSO at all |  | Proxy provider present; not tested (Claude 2026-11-06) |  |  |
| UX built around self-service for the org, the lower skill threshold the better | | | | |
| **Also** | | | | |
| Licence | Apache-2.0 (Claude 2026-11-06) | Core per repo LICENSE; enterprise directory under a paid-use licence (Claude 2026-11-06) | AGPL-3.0 (Claude 2026-11-06) | CDDL 1.1 (Claude 2026-11-06) |
| Could we fix it ourselves | | | | |
| Idle memory, app and database | 857 MiB (Claude 2026-11-06) | 944 MiB (server, worker, database, redis) (Claude 2026-11-06) | 204 MiB (Claude 2026-11-06) | 1.35 GiB (OpenAM and OpenDJ) (Claude 2026-11-06) |
| Boot to ready | 69 s (Claude 2026-11-06) | 283 s on first start (migrations) (Claude 2026-11-06) | 20 to 37 s (Claude 2026-11-06) | About 4 to 5 min from first start to configured (Claude 2026-11-06) |
| Work to a first working SSO | One scripted run, about 10 admin API calls (Claude 2026-11-06) | No admin token without the UI; about 40 lines in the Django shell; grant type had to be added (Claude 2026-11-06) | About 10 API calls plus the groups Action; first boot needs a machine user for a token (Claude 2026-11-06) | About 3 REST calls for the provider plus 2 client updates; defaults needed RS256, PKCE off, consent skipped (Claude 2026-11-06) |

## Notes

---

SSO coverage is a huge question here, most FOSS **DOES NOT SUPPORT SSO** and the cost to add it can easily be thousands of dollars per project (not accounting for additional support overhead if we have to fork it to do so). We probably need some sort of target coverage for success/failure here or it isn't worth our time. - William Roush 2026-08-10

---

LDAP, from William's hands-on testing on another deployment (devops list, 2026-10-18), in his words: Authentik's "LDAP sync" works poorly, and "the UI in general is kind of a struggle bus and really poor error messaging". Keycloak "doesn't run its own LDAP server internally, can just hook into one". And "Chattanooga Digital didn't really have a strong reliance on LDAP", which fits the LDAP server row sitting under Nice to have. Sync (pulling users in from another directory) is not the same as that row (serving LDAP to apps). His fuller report is to follow. - Jon Pohlner 2026-10-18

---

Cells marked Claude come from running each candidate in a local Docker copy beside a Nextcloud and a Drupal test instance, on 2026-11-06. Replace the mark with your initials once you have checked the cell yourself. Empty cells were not checked.
