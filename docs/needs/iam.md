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

## Evaluation checklist

A tick is `INITIALS YYYY-MM-DD`, per the [portfolio rules](../PORTFOLIO.md#validation-checkboxes). A measured value carries its date. An empty cell is unchecked. All four candidates run on staging with one account per evaluator, see [How to take part](#how-to-take-part).

### 1. Requirements

| Requirement | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| OIDC provider, verified with a real client | [ ] | [ ] | [ ] | [ ] |
| SAML provider, verified with a real client | [ ] | [ ] | [ ] | [ ] |
| MFA: TOTP enrolled and used | [ ] | [ ] | [ ] | [ ] |
| MFA: passkey enrolled and used | [ ] | [ ] | [ ] | [ ] |
| Self-service password reset | [x] `JP 2026-09-19` `RA 2026-09-21` | [x] `JP 2026-09-19` `RA 2026-09-21` | [x] `JP 2026-09-19` `RA 2026-09-21` `JP 2026-09-23` | [x] `JP 2026-09-19` `RA 2026-09-21` |
| Self-service profile edit | [ ] | [ ] | [ ] | [ ] |
| Group claims reach a client app | [ ] | [ ] | [ ] | [ ] |
| Disabling the user locks them out of a client app | [ ] | [ ] | [ ] | [ ] |
| None of the above behind a paid tier | [ ] | [ ] | [ ] | [ ] |

Password reset was verified by requesting it from each login page and receiving the set-password mail at a real mailbox.

Evaluator findings on the reset flow, quoted. Scoped to password reset, no ranking.

| | William, 2026-09-19 |
|---|---|
| Authentik | *"Authentik's email renders with a giant logo lol"* |
| OpenAM | *"OpenAM sent a broken e-mail that... frankly isn't acceptable, makes me reset my password, then makes me change it right after resetting it... that's... awful"* |
| Zitadel | *"Zitadel doesn't even have a password reset page for me to use"* |
| Authentik + OpenAM | *"I don't appear to be an admin on Authentik or OpenAM"* |

| | Rob, 2026-09-21 |
|---|---|
| Keycloak | *"Still has an active UI in click-through after submission - so I ask myself, did it work?"* |
| Authentik | *"Landed at a better next steps style page - had to login twice after reset, may have been a one-time issue"* |
| OpenAM | *"Gives first and last name submission as an additional option for reset... Same loop Will mentioned, must reset again after resetting + says the password must be different (how would it know?)"* |
| Zitadel | *"Register flow is different - welcome back wording on page. Tried raitchison and did not work, raitch@pm.me did. Received password has changed email unlike other three systems. Sent immediately to 2-factor screen on next login."* |

Does completing a self-service reset clear the forced-change flag?

| | |
|---|---|
| Keycloak | Yes. `requiredActions` is `[]` for `raitchison` and `wroush`, who completed it, and `['UPDATE_PASSWORD']` for the three who have not |
| Zitadel | Yes. Walked end to end 2026-09-23: reset, set password, signed in with no second prompt |
| OpenAM | No. `ds-cfg-force-change-on-reset: true` makes a self-service reset administrative, because OpenAM sets the password by binding to the directory as the administrator. A second change is demanded at once |
| Authentik | No. The recovery flow does not clear the `reset_password` attribute, so the next login prompts again (measured 2026-09-23). Fixable in our blueprint |

OpenAM keeps no password history (`ds-cfg-password-history-count` and `ds-cfg-password-history-duration` are 0), so the must-differ check compares against the current password.

Zitadel reset, walked 2026-09-23 on a real account:

| Step | Result |
|---|---|
| Login name `wroush` | "User could not be found", no password screen, no reset link |
| Login name is the account's email address | Password screen with a Reset Password link |
| Click it | "Password Reset Link Sent" |
| Mail | In the inbox, not spam, after 3 seconds, from `no-reply@get.chattanooga.digital` |
| Follow the link, set a password | "Password successfully set" |
| Sign in with the new password | Succeeded |

Zitadel login names are email addresses: the five accounts were created with the email in `userName`, the other three systems with short names, and `userLoginMustBeDomain` is off. The Reset Password link only appears on the password screen, so a login name that does not resolve never reaches it. A user who never completed initialisation (`USER_STATE_INITIAL`) gets the password screen with no Reset Password link. The accounts are not renamed during the evaluation.

Paid tier: Authentik ships `authentik/enterprise/` under a separate EE licence (present at tag 2026.8.3). Which features sit behind it is unchecked.

SSO coverage target: not set. Hubzilla is an OIDC provider with no client support (2026-08-12). Drupal's official OIDC client module is alpha, its SAML module stable (2026-08-20).

### 2. Nice to have

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Multi-tenancy | [ ] | [ ] | [ ] | [ ] |
| LDAP server for LDAP-only apps | [ ] | [ ] | [ ] | [ ] |
| Forward auth through Traefik | [ ] | [ ] | [ ] | [ ] |
| Self-service UX: a non-admin can find their way | [ ] | [ ] | [ ] | [ ] |
| Adding a member is something an officer would do unaided | [ ] | [ ] | [ ] | [ ] |

### 3. Project health

Measured 2026-09-20 from each project's GitHub repository unless stated.

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Licence of the repository today | Apache-2.0 | MIT for the server; a separate EE licence for `authentik/enterprise/`; CC BY-SA 4.0 for the docs | AGPL-3.0 on the v4 line | CDDL-1.1 |
| Licence of the version staging runs | Apache-2.0 (26.7.4) | as above (2026.8.3) | Apache-2.0 (v2.71.0) | CDDL-1.1 (15.0.3) |
| Implementation language | Java | Python server, Go outposts | Go | Java on Tomcat, config in LDAP |
| Latest release | 26.7.4 on 2026-09-16 | 2026.8.3 on 2026-09-17 | v4.17.3 on 2026-09-04 | 16.1.3 on 2026-09-18 |
| Two releases before that | 26.7.3 on 2026-08-31 | 2026.8.2 and 2026.5.7 on 2026-09-09 | v4.17.2 on 2026-08-31, v4.17.1 on 2026-08-14 | 16.1.2 on 2026-07-20, 16.1.1 on 2026-06-17 |
| Last push to the repository | 2026-09-20 | 2026-09-19 | 2026-09-18 | 2026-09-18 |
| Open issues / stars | 3,269 / 36.9k | 1,100 / 25.7k | 1,199 / 15.1k | 17 / 895 |
| Maintainer diversity (more than one organisation) | [ ] | [ ] | [ ] | [ ] |
| Security advisories: how many, how fast fixed | [ ] | [ ] | [ ] | [ ] |
| Vulnerability reporting instructions published | [ ] | [ ] | [ ] | [ ] |
| Documentation current and usable by a non-expert | [ ] | [ ] | [ ] | [ ] |
| Governance and long-term support stated | [ ] | [ ] | [ ] | [ ] |
| Exit: users and groups can be exported, clients re-pointed | [ ] | [ ] | [ ] | [ ] |

### 4. Cost to run

Measured on the staging Swarm on 2026-09-20, from the Docker API and the four stacks as deployed.

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Containers | 2: app, Postgres 18 | 4: server, worker, Postgres 16, Redis 7 | 2: app, Postgres 17 | 2: Tomcat app, OpenDJ |
| Declared memory limits | 1500M + 512M | 1G + 1G + 512M + 192M | 1G + 512M | 1500M + 512M |
| Image size on disk | 454 MB, db 289 MB | 1,246 MB, plus db and redis | 133 MB, db 283 MB | 753 MB, OpenDJ 386 MB |
| Version deployed vs latest upstream | 26.7.4 = latest | 2026.8.3 = latest | v2.71.0; stack file names v4.17.3 | 15.0.3; latest is 16.1.3 |
| Fully declarative from the stack file | yes | yes; the forced-change flow ships as a blueprint via a Swarm config | yes, except SMTP, which is instance state read at creation only | no: configurator run, two LDAP schema loads and a realm chain change are post-deploy steps |
| Mail configured from the stack environment | no, console after first boot | yes | at instance creation only | no, console or `ssoadm` after first boot |
| Invitation without a credential (set-password link) | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` |
| Force a password change at first login | one field per user | a whole flow, shipped as a blueprint | one field per user | realm chain change that also locks the admin out of the default login |
| Staging runs the PR branch head | yes | yes | yes | yes |
| Backup and restore proven | [ ] | [ ] | [ ] | [ ] |
| What every client app does when the IdP is down | [ ] | [ ] | [ ] | [ ] |

The four stacks were started on 2026-09-16. All four accepted a sign-in and sent mail by 2026-09-19.

### How to take part

Each evaluator has an account on all four. To set a password, open the login page, choose the forgotten-password route, enter your username or email and follow the mailed link.

| | Where | Username form |
|---|---|---|
| Keycloak | `https://keycloak.staging.chattanooga.digital/` | short name |
| Authentik | `https://authentik.staging.chattanooga.digital/` | short name |
| OpenAM | `https://openam.staging.chattanooga.digital/openam/` | short name |
| Zitadel | `https://zitadel.staging.chattanooga.digital/` | email address |

Start with the [walkthrough](iam-walkthrough.md): it has you create a least-privilege account on each system first.

Admin on the evaluator accounts, measured 2026-09-22:

| | Evaluator accounts are admin | Granted |
|---|---|---|
| Keycloak | yes | at deployment |
| Authentik | yes | 2026-09-22, via a `Co-op Admins` group |
| Zitadel | yes | 2026-09-22, `IAM_OWNER` + `ORG_OWNER` |
| OpenAM | no | blocked, see the walkthrough's [OpenAM section](iam-walkthrough.md#openam) |

Tick what you checked, with initials and date. Notes go on the candidate's portfolio page. A mail that never arrives is a result for the candidate that failed to send it.

### Open questions

- Federation between IAM instances: members with their own infrastructure may need their own provider. One, or a federation?
- The coverage target: what share of the portfolio must be able to be a client.

## Notes

---

SSO coverage is a huge question here, most FOSS **DOES NOT SUPPORT SSO** and the cost to add it can easily be thousands of dollars per project (not accounting for additional support overhead if we have to fork it to do so). We probably need some sort of target coverage for success/failure here or it isn't worth our time. - William Roush 2026-08-10
