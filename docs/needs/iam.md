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

Item 4 of the 2026-09-16 meeting agenda. This is the part of the page that gets
filled in by *using* the candidates rather than reading about them. All four are
deployed on staging with an account for each evaluator; see
[How to take part](#how-to-take-part).

The criteria come from three places. The [Requirements](#requirements) and
[Nice to have](#nice-to-have) lists above. The three guides Greg circulated on
2026-08-27 (Wheeler's *How to Evaluate OSS/FS Programs*, the OpenSSF *Concise
Guide for Evaluating Open Source Software*, and LeadDev's *12 things to consider
when assessing open source software*), reduced to what applies to software we
deploy off the shelf and operate rather than build with. And two points Rob made
on 2026-09-01: licence is critical, and the implementation language decides
whether we can fix it ourselves when it breaks.

Marking follows the [portfolio rules](../PORTFOLIO.md#validation-checkboxes): a
tick means *I personally checked this*, initialled and dated. A measured value
carries a date the same way. An empty cell means nobody has checked it yet. That
is a finding, not a gap to fill by assumption.

### Purpose and sponsor

Sponsor: the cooperative, on behalf of every member. Purpose: a member signs in
once and reaches every co-op service, and the co-op rather than a platform holds
the identity. Greg's fuller statement is in the 2026-08-27 thread *FOSS
Evaluation and IAM/IdP*: authentication by passkeys, passwords and other factors;
authorisation by role; automated account lifecycle; governance and monitoring of
access; all over standard protocols.

### 1. Requirements. Each must pass.

| Requirement | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| OIDC provider, verified with a real client | [ ] | [ ] | [ ] | [ ] |
| SAML provider, verified with a real client | [ ] | [ ] | [ ] | [ ] |
| MFA: TOTP enrolled and used | [ ] | [ ] | [ ] | [ ] |
| MFA: passkey enrolled and used | [ ] | [ ] | [ ] | [ ] |
| Self-service password reset | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` |
| Self-service profile edit | [ ] | [ ] | [ ] | [ ] |
| Group claims reach a client app | [ ] | [ ] | [ ] | [ ] |
| Disabling the user locks them out of a client app | [ ] | [ ] | [ ] | [ ] |
| None of the above behind a paid tier | [ ] | [ ] | [ ] | [ ] |

Password reset: verified by requesting it from each login page and receiving the
set-password mail from each system at a real mailbox on 2026-09-19. Keycloak
offers *Forgot Your Password*, Zitadel *Reset Password*, OpenAM advertises
`forgotPassword: true`, Authentik exposes its recovery flow on the login page.

Paid tier: Authentik ships an `authentik/enterprise/` directory under a separate
EE licence (present at tag 2026.8.3). Which features sit behind it, and whether
any requirement above does, is unchecked.

SSO coverage across the portfolio is a target we have not set. William's 2026-08-10
note below says the evaluation is not worth the time without one. Two constraints
on it are already measured: Hubzilla acts as an OIDC *provider* and shows no
client support (2026-08-12), and Drupal's official OIDC client module is alpha
while its SAML module is stable, though William cautions SAML brings its own
complications (2026-08-20).

### 2. Nice to have

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Multi-tenancy | [ ] | [ ] | [ ] | [ ] |
| LDAP server for LDAP-only apps | [ ] | [ ] | [ ] | [ ] |
| Forward auth through Traefik | [ ] | [ ] | [ ] | [ ] |
| Self-service UX: a non-admin can find their way | [ ] | [ ] | [ ] | [ ] |
| Adding a member is something an officer would do unaided | [ ] | [ ] | [ ] | [ ] |

### 3. Project health

Measured 2026-09-20 from each project's GitHub repository unless stated. Stars
and issue counts are a proxy for adoption and activity, nothing more.

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Licence of the repository today | Apache-2.0 | MIT for the server; a separate EE licence for `authentik/enterprise/`; CC BY-SA 4.0 for the docs | **AGPL-3.0** on the v4 line | CDDL-1.1 |
| Licence of the version staging runs | Apache-2.0 (26.7.4) | as above (2026.8.3) | **Apache-2.0 (v2.71.0)**. The licence changed between the version deployed and the version the stack file names | CDDL-1.1 (15.0.3) |
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

Which language the co-op can actually fix is the question Rob raised, not which
language is better. Fill it in against who is on the ops team when the decision
is made.

### 4. Cost to run

Measured on the staging Swarm on 2026-09-20 (services, limits and image sizes
from the Docker API) and from the four stacks as deployed.

| | Keycloak | Authentik | Zitadel | OpenAM |
|---|---|---|---|---|
| Containers | 2: app, Postgres 18 | 4: server, worker, Postgres 16, Redis 7 | 2: app, Postgres 17 | 2: Tomcat app, OpenDJ |
| Declared memory limits | 1500M + 512M | 1G + 1G + 512M + 192M | 1G + 512M | 1500M + 512M |
| Image size on disk | 454 MB, db 289 MB | 1,246 MB, plus db and redis | 133 MB, db 283 MB | 753 MB, OpenDJ 386 MB |
| Version deployed vs latest upstream | 26.7.4 = latest | 2026.8.3 = latest | **v2.71.0**; stack file names v4.17.3 | **15.0.3**; latest is 16.1.3 |
| Fully declarative from the stack file | yes | yes; the forced-change flow ships as a blueprint via a Swarm config | yes, except SMTP, which is instance state read at creation only | **no**: configurator run, two LDAP schema loads and a realm chain change are post-deploy steps |
| Mail configured from the stack environment | no, console after first boot | yes | at instance creation only | no, console or `ssoadm` after first boot |
| Invitation without a credential (set-password link) | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` | [x] `JP 2026-09-19` |
| Force a password change at first login | one field per user | a whole flow, shipped as a blueprint | one field per user | realm chain change that also locks the admin out of the default login |
| Staging runs the PR branch head | yes | yes | yes | yes |
| Backup and restore proven | [ ] | [ ] | [ ] | [ ] |
| What every client app does when the IdP is down | [ ] | [ ] | [ ] | [ ] |

Time to a working evaluation instance: the four stacks were started on 2026-09-16
and all four accepted a sign-in and sent mail by 2026-09-19. Commits after the
split into one branch each are a fair proxy for the trouble: Keycloak 4, Zitadel
5, OpenAM 5, Authentik 8. The traps that cost the time are written up once each,
in the stack READMEs, so the next person does not pay for them again:

- Keycloak ([PR #15](https://github.com/Chattanooga-Digital/stack/pull/15), `stacks/keycloak/README.md`): renamed admin variables silently
  ignored; `--optimized` skipping the build step.
- Authentik ([PR #16](https://github.com/Chattanooga-Digital/stack/pull/16), `stacks/authentik/README.md`): no per-user forced change, so a
  four-object flow; a blueprint entry is a whole object, and one bad entry fails
  the whole file without a message.
- Zitadel ([PR #17](https://github.com/Chattanooga-Digital/stack/pull/17), `stacks/zitadel/README.md`): the admin login name is
  `admin@<org>.<domain>`, and the bare name fails with `NotHuman`; SMTP is
  instance state, so changing the variables and redeploying changes nothing.
- OpenAM ([PR #18](https://github.com/Chattanooga-Digital/stack/pull/18), `stacks/openam/README.md`): the directory advertises the suffix
  without creating the base entry; the user store needs OpenAM's own schema loaded
  first; the configurator's last-step `500` names neither.

Two deployment findings that are about us rather than the candidates. All four
were first deployed with a placeholder mail relay that passed every check this
repo had, so none could send an invitation until 2026-09-19; [stack PR #19](https://github.com/Chattanooga-Digital/stack/pull/19)
makes the validator reject placeholders. And giving all four a working relay reused one
Resend credential across them, so revoking any one of them now means rotating all
of them.

### How to take part

Each evaluator already has an account on all four. There is no password to
receive: open the login page, choose the forgotten-password route, enter your
username or email, and set your own from the link that arrives. Nobody else sees
it.

| | Where | Username form |
|---|---|---|
| Keycloak | `https://keycloak.staging.chattanooga.digital/` | short name |
| Authentik | `https://authentik.staging.chattanooga.digital/` | short name |
| OpenAM | `https://openam.staging.chattanooga.digital/openam/` | short name |
| Zitadel | `https://zitadel.staging.chattanooga.digital/` | email address |

Try the things above that have an empty box. Record what you checked by ticking
it with your initials and the date. Anything that surprised you, good or bad,
goes as a note on that candidate's portfolio page. If a mail never turns up, that
is a result about the candidate that failed to send it; say so rather than
retrying quietly.

### Open questions for the task force

- **Federation between IAM instances.** Greg, 2026-09-01: members with their own
  infrastructure may need their own identity provider. Do we run one, or a
  federation of them?
- **The coverage target.** What fraction of the portfolio must be able to be a
  client for the whole exercise to count as a success?
- **Which Zitadel is under evaluation.** Staging runs v2.71.0 under Apache-2.0;
  the current line is v4 under AGPL-3.0, with its new login served by a separate
  container. Evaluate the one we would actually run.
- **Same for OpenAM**: staging runs 15.0.3, upstream is on 16.1.3.

## Notes

---

SSO coverage is a huge question here, most FOSS **DOES NOT SUPPORT SSO** and the cost to add it can easily be thousands of dollars per project (not accounting for additional support overhead if we have to fork it to do so). We probably need some sort of target coverage for success/failure here or it isn't worth our time. - William Roush 2026-08-10

---

Evaluation checklist added at Greg's request: 2026-08-27 ("combine key elements from these to create a review protocol and scoresheet"), 2026-09-01 ("make a checklist"), the 2026-09-16 agenda's item 4, and 2026-09-19 ("an initial version of the evaluation framework"). Everything with a date beside it was measured on staging or on the upstream repository on that date, and the method is stated with it. The rows with empty boxes are the evaluators' work and were left empty on purpose. Two things I would not have known from the stack files alone: the Zitadel instance on staging is v2.71.0 under Apache-2.0 while the stack file names v4.17.3 under AGPL-3.0, so the licence differs between what is deployed and what is declared; and none of the four could send mail until 2026-09-19 because each was deployed with a placeholder relay that every check accepted. - Jon Pohlner 2026-09-20
