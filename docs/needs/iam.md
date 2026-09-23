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
| Self-service password reset | [x] `JP 2026-09-19` `RA 2026-09-21` | [x] `JP 2026-09-19` `RA 2026-09-21` | [x] `JP 2026-09-19` `RA 2026-09-21` `JP 2026-09-23` | [x] `JP 2026-09-19` `RA 2026-09-21` |
| Self-service profile edit | [ ] | [ ] | [ ] | [ ] |
| Group claims reach a client app | [ ] | [ ] | [ ] | [ ] |
| Disabling the user locks them out of a client app | [ ] | [ ] | [ ] | [ ] |
| None of the above behind a paid tier | [ ] | [ ] | [ ] | [ ] |

Password reset: verified by requesting it from each login page and receiving the
set-password mail from each system at a real mailbox on 2026-09-19. Keycloak
offers *Forgot Your Password*, Zitadel *Reset Password*, OpenAM advertises
`forgotPassword: true`, Authentik exposes its recovery flow on the login page.

**Two people have now driven these systems rather than read about them.**
William Roush reported four findings in the IAM Evaluation Talk room on
**2026-09-19**, which is the earliest evaluation anyone did; Rob Aitchison walked
the whole reset flow on all four on **2026-09-21**. Both are quoted rather than
summarised, because the wording is the finding, and both are scoped narrowly and
carry no ranking.

*(This page previously called Rob's the first. That was wrong, and wrong in a way
worth naming: William's messages sat in a Talk room nobody re-reads, which is the
same reason his report of the admin gap went unactioned for three days.)*

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

Only Keycloak leaves the person unsure whether the reset worked, which matters more
for the co-op's stated goal of a low skill threshold than any feature in the table
above. Only Zitadel confirms the change by mail.

🔴 **CORRECTED 2026-09-23: the OpenAM double reset is the PRODUCT'S, and this page
previously filed it as ours.** Yesterday it said the loop was a setting we chose and
must not be scored against the candidate. That is wrong, and wrong in OpenAM's
favour, so the row was about to be discounted for no reason.

Forcing a change on a credential somebody else set is best practice, was settled on
2026-09-19, and is applied to **all four** through each product's own mechanism. The
policy is uniform. What differs is what each one does when the user then completes a
**self-service** reset:

| | does completing a self-service reset clear the forced-change flag? |
|---|---|
| **Keycloak** | **Yes.** `requiredActions` is `[]` for `raitchison` and `wroush`, the two who completed it, and still `['UPDATE_PASSWORD']` for the three who have not |
| **Zitadel** | **Yes.** Walked end to end 2026-09-23 — reset, set password, signed straight in, no second prompt |
| **OpenAM** | **No.** `ds-cfg-force-change-on-reset: true` makes a self-service reset count as an *administrative* one, so the chain demands a second change immediately |
| **Authentik** | **Unmeasured.** Rob's *"had to login twice after reset"* may be this same behaviour, and is one test away |

So William's *"makes me reset my password, then makes me change it right after
resetting it... that's... awful"* is a fair hit on the product. Removing the flag,
which this page previously recommended, would have hidden a real difference between
candidates rather than corrected a mistake of ours.

Rob's aside — *"how would it know?"* — still has its answer, and it is not password
history: `ds-cfg-password-history-count: 0` and `ds-cfg-password-history-duration: 0
seconds`, so nothing is remembered. It compares against the **current** password,
which it holds.

*(The other attribution on this page — the Zitadel login name — really is ours, and
is settled immediately below.)*

🟢 **SETTLED 2026-09-23. Zitadel's self-service password reset works, and
William's report was accurate.** Both were true at once, because the reset link is
only reachable once a valid login name has been entered, and the name he was told
to use does not exist on Zitadel.

Measured end to end, on a real account, in this order:

| step | result |
|---|---|
| login name `wroush` | *"User could not be found"*. No password screen, and **no reset link anywhere on the page** |
| login name `william.roush@roushtech.net` | password screen, carrying a **Reset Password** link |
| clicking it | *"Password Reset Link Sent"* |
| the mail | arrived at the inbox (not spam) **3 seconds** later, from `no-reply@get.chattanooga.digital` |
| following the link, setting a password | *"Password successfully set"* |
| signing in with that new password | **succeeded** |

So the tick stands, and `RA 2026-09-21` was right to set it. The row now also
carries `JP 2026-09-23` for the full chain rather than just the mail.

🔴 **The cause is ours, and it is not what this page previously said.** It was
written up as Zitadel qualifying login names with the organisation's domain. That
is false on this instance: `userLoginMustBeDomain` is off, and a user created as
`turtlewolfe-test` logs in as exactly `turtlewolfe-test`. What actually happened is
that **the five Zitadel accounts were created with the email address in the
`userName` field**, while the same five accounts on Keycloak, Authentik and OpenAM
were created with short names. Measured in `projections.users14`: every account
created 2026-09-19 has `username` identical to its email.

The invitation then told everyone to use their short name. On three systems that
was right; on Zitadel it names an account that does not exist.

**And no mail could have corrected them.** The Zitadel mail sent on 2026-09-19 was
a *Reset password* mail, which does not mention a username. Zitadel's *Initialize
User* mail does — *"Use the username turtlewolfe-test to login"* — but that is sent
on account creation and was not used for these five. There was no way for William
to learn his Zitadel login name from anything he had been sent.

🟡 **A separate, real finding fell out of the same test.** A Zitadel user who has
never completed initialisation gets the password screen with **no Reset Password
link at all** — confirmed against a freshly created account in `USER_STATE_INITIAL`.
Self-service recovery therefore does not cover the member most likely to need it:
the one who never finished signing up the first time. That is the product's
behaviour, not our configuration, and belongs in the scoring.

🟢 **Decided 2026-09-23: the Zitadel accounts are NOT being renamed.** It would
remove a confound we introduced, and it would also change the login name of people
who are part-way through evaluating, for our tidiness rather than their benefit.
The inconsistency stays for the duration and is recorded here instead: email
address on Zitadel, short name on the other three.

🔴 **And the general rule it comes from: no evaluation system changes underneath
the evaluators without telling them first**, in the Talk room they actually use.
People are mid-evaluation; a system that changes without warning wastes their work
and the trust that got them to do it, and their attention is the scarce resource
here, not the server.

For the OpenAM rebuild the notice is short rather than a countdown, because
**there is almost nothing anyone can do on OpenAM right now**: of the nine
requirements above, one is ticked, seven need an administrator nobody has, and only
*self-service profile edit* remains open to an ordinary user.

🔴 **The real gate on that rebuild is reproducibility, not elapsed time.** There is
**no post-install script for this stack** — confirmed on `iam/openam`, which carries
only the generic `scripts/validate.sh`. `stacks/openam/README.md` says so itself: a
fresh deploy comes up with the stock DataStore chain, no forced password change and
no accounts. So rebuilding today would replace the exact configuration William and
Rob tested against, with nothing in the repository able to restore it, and their
OpenAM findings would stop describing the deployed system. Either script the
post-install first, or accept that those findings reset with it.

**Which makes one question worth answering before any of that: is OpenAM still a
live candidate?** It is the only one of the four nobody can administer, and the only
one whose mail an evaluator called *"frankly isn't acceptable"*. If it is going to be
dropped, both the rebuild and the script are wasted work.

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

**There is a walkthrough: [Walking the four candidates](iam-walkthrough.md)**, whose
live copy is open to every co-op account, not only the evaluators:

https://cloud.chattanooga.digital/apps/collectives/IAM-Evaluation-5/IAM-evaluation-walking-the-four-candidates-3198

It
starts by having you create a least-privilege twin of yourself on each system,
because every requirement in the table above is experienced by somebody who is
*not* an administrator, and all five of you are now administrators.

🔴 **Admin was measured on 2026-09-22 and it was granted on one system of four,
not four.** William's Deck card #103 asked for admin accounts for all five
evaluators. Five accounts existed everywhere; the privilege existed only on
Keycloak. Authentik and Zitadel were corrected the same day. OpenAM was not, and
cannot be — see the walkthrough's [OpenAM
section](iam-walkthrough.md#openam) — because its `amadmin` credential is not
held in the stack environment or any secret store we control.

| | evaluator accounts are admin | granted |
|---|---|---|
| Keycloak | yes | at deployment |
| Authentik | yes | 2026-09-22, via a `Co-op Admins` group |
| Zitadel | yes | 2026-09-22, `IAM_OWNER` + `ORG_OWNER` |
| OpenAM | **no** | blocked |

This matters for how Rob's notes above are read. They were taken from a
non-administrator seat on three of the four, which is the right seat for a
password reset and the wrong one for everything else. **No admin console,
delegation model or policy screen on any candidate has been evaluated by
anybody.**

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
