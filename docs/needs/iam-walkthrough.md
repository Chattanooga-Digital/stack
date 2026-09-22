# IAM: walking the four candidates

[Needs index](../NEEDS.md) · [IAM need and checklist](iam.md)

This is the companion to the [evaluation checklist](iam.md#evaluation-checklist).
The checklist says *what* to decide; this says *what to do on a Tuesday evening*
to be able to decide it.

🔴 **The evaluators read this in Nextcloud, not here.** The same walkthrough is a
page in the **Operations** collective, whose five members are exactly the five
evaluators:

https://cloud.chattanooga.digital/apps/collectives/Operations

That is the copy people will actually open, and where their notes go. This file
is the version-controlled copy; if the two drift, the collective is what the
evaluation was run against. Evaluation notes were, until 2026-09-22, sitting in
Greg's and Rob's **private** folders where neither could read the other's, which
is the problem the collective page exists to stop repeating.

It exists because of a measurement taken on 2026-09-22. William's Deck card #103
asked for admin accounts for Greg, Adam, Jon, Rob and Will on all four
candidates. Five accounts did exist on all four. **Admin existed on one.** The
accounts were created and the privilege was never granted, and nothing in the
process would have said so — an ordinary account and an administrator's account
are indistinguishable from the invitation mail.

| | admin, before | admin, now |
|---|---|---|
| Keycloak | all five | all five |
| Authentik | nobody but `akadmin` | all five, via a `Co-op Admins` group |
| Zitadel | nobody but the built-in admin | all five, `IAM_OWNER` + `ORG_OWNER` |
| OpenAM | nobody but `amadmin` | **still nobody** — see [OpenAM](#openam) |

## The target: ten accounts on each, then more

Five evaluators, each holding **two** accounts on every system:

1. the administrator's account you already have, and
2. a **least-privilege twin** that you create yourself, named `<username>-test`.

That is ten per system before anyone else is invited, and inviting other co-op
members as beta testers is the point rather than a stretch goal. A system that is
pleasant with ten accounts and five administrators is not yet evidence of
anything; the co-op has more members than that, and the failures that matter show
up when real people who did not build it try to sign in.

### Why the twin comes first, before anything else

Three reasons, and the third is the one that is easy to miss.

- **It is the most instructive first task an IAM system offers.** Creating a user
  walks you through the account model, the group or role model, and the credential
  handover in one go. You learn more about a product in the ten minutes of making
  one account than in an hour of reading its documentation.
- **It is the only way to see what a member sees.** Every requirement in the
  checklist — self-service reset, profile edit, MFA enrolment, group claims
  reaching an app — is experienced by somebody who is *not* an administrator. An
  admin account cannot tell you whether the member's path is any good, and an
  admin account is what all five of you now have.
- **Least privilege is a habit, and this is where it costs nothing to build.** Do
  the routine administrative browsing as the twin. Reach for the admin account
  deliberately, when a task needs it. If that feels inconvenient on one of these
  products, write that down — it is a finding about the product, not about you.

**What "least privilege" means on each system** is the state we measured on
2026-09-22 as the default for an account nobody has granted anything to:

| | a least-privilege account is one that | how to confirm |
|---|---|---|
| Keycloak | holds only `default-roles-master`, and **not** the `admin` realm role | it can open the account console, not `/admin/master/console/` |
| Authentik | belongs to **no group** — admin is carried by the group, never by the user | no *Admin interface* link appears after login |
| Zitadel | holds no `IAM_OWNER` and no `ORG_OWNER` membership | the console loads with its management sections absent |
| OpenAM | is a plain entry under `ou=people` with no delegation privilege | no *Realms* navigation after login |

### Naming

`<username>-test`, lower case, no other decoration: `wroush-test`,
`glaudeman-test`, `azahorscak-test`, `raitchison-test`, `turtlewolfe-test`. Give
it an address you actually receive mail at, because half of what is being
evaluated arrives by mail. A `+` tag on your own address works on every mail
system the co-op runs: `you+test@example.org`.

Beta testers keep their ordinary name. They are real members, not fixtures.

---

## Keycloak

Sign in at `https://keycloak.staging.chattanooga.digital/admin/master/console/`
with your short username. All five of you already hold the `admin` realm role on
the `master` realm.

1. **Make the twin.** *Users* → *Add user*. Username `<you>-test`, fill the email,
   and turn **Email verified** off so you exercise the mail path. Save, then
   *Credentials* → *Set password* with **Temporary** on, or better, *Credential
   Reset* → send an email action so no password is ever chosen for them.
2. **Confirm it is powerless.** Private window, sign in as the twin at
   `https://keycloak.staging.chattanooga.digital/realms/master/account/`. Then try
   `/admin/master/console/` in the same window: it must refuse. If it does not,
   that is a finding.
3. **Invite a beta tester.** Same *Add user* route, then *Credential Reset* with
   the *Update Password* action so they set their own.
4. **Judge.** Rob's note on this one is already in the checklist and is the thing
   to confirm or contradict: *"Still has an active UI in click-through after
   submission - so I ask myself, did it work?"*

## Authentik

Sign in at `https://authentik.staging.chattanooga.digital/` with your short
username, then follow **Admin interface** in the user menu, or go straight to
`https://authentik.staging.chattanooga.digital/if/admin/`.

Your admin rights arrive through a group called **Co-op Admins**, created
2026-09-22 with `is_superuser` set. Authentik has no per-user admin flag at all —
`authentik_core_user` carries no such column — which is itself worth knowing when
you judge its permission model.

1. **Make the twin.** *Directory* → *Users* → *Create*. Username `<you>-test`,
   a real email. **Add it to no group.** That is the least-privilege state.
2. **Confirm it is powerless.** Private window, sign in as the twin: no *Admin
   interface* entry should appear, and `/if/admin/` should refuse directly.
3. **Invite a beta tester.** Create the user, then use the recovery link rather
   than setting a password — *Directory* → *Users* → the user → *Create recovery
   link*, or let them use the forgotten-password route on the login page.
4. **Judge.** Rob: *"Landed at a better next steps style page - had to login twice
   after reset, may have been a one-time issue."* Confirm or clear the double
   login. Also check whether anything you want sits behind the `enterprise/`
   licence.

## Zitadel

Sign in at `https://zitadel.staging.chattanooga.digital/ui/console`.

🔴 **Your login name is your email address, not your short username.** Zitadel
qualifies login names with the organisation's domain. This is the single thing
that has already cost an evaluator a session: Rob tried `raitchison`, it failed,
and `raitch@pm.me` worked. The invitation mail led with the short name and was
wrong to.

All five of you now hold `IAM_OWNER` on the instance and `ORG_OWNER` on the
organisation, granted 2026-09-22.

1. **Make the twin.** *Users* → *New*. Note the login name Zitadel composes for
   it, because that — not what you typed — is what signs in. Grant it **no**
   manager role: do not add it under *Organization* → *Members*.
2. **Confirm it is powerless.** Private window, sign in as the twin using its full
   login name. The console should load with nothing to manage.
3. **Invite a beta tester.** Create the user and let Zitadel send the initial mail
   rather than setting a password.
4. **Judge.** Zitadel is the only one of the four that mails a confirmation when a
   password changes, which Rob noticed and liked. It also sends you to a
   second-factor screen on the next login. Decide whether that is reassuring or
   an obstacle for a member who is not technical.

## OpenAM

🔴 **Nobody can administer this one, including us.** Measured 2026-09-22: the five
evaluator accounts are plain entries under `ou=people` with no delegation
privilege, `ou=groups` is empty, and the `amadmin` credential is not held in the
stack environment, in any secret store, or anywhere else we control. The stack
environment carries only `DIRECTORY_PASSWORD`, which is OpenDJ's Directory
Manager and is not `amadmin`.

So the exercises above cannot be run here yet, and that is a finding rather than a
chore. Three things follow from it, in order of what they cost:

- **It is a genuine mark against the candidate.** Every other system in this
  evaluation offers a documented way back in when an administrator credential is
  lost — Authentik ships a recovery-key command, Keycloak and Zitadel both hold a
  working credential in the stack environment. OpenAM's recovery path is to hold
  the password you were given at configuration time. For a cooperative whose
  stated goal is a low skill threshold, "do not lose this" is a weak answer.
- **It is also partly ours.** `amadmin`'s password was set by hand when the
  instance was configured on 2026-09-18 and was never written into the stack
  environment or a secret store. The same is true of the realm authentication
  chain: `stacks/openam/README.md` already flags that the configuration is *not*
  in the compose file and that a fresh deploy comes up without it.
- **Getting back in means redeploying.** A fresh deploy of the stack restores a
  known administrator credential, at the cost of the five accounts and the realm
  chain, both of which are scripted and were built once already. That is a
  decision for the task force, not a step to take quietly, and it should be paired
  with putting the credential in the stack environment so this cannot recur.

Until then, the rows in the checklist that need an administrator stay empty for
OpenAM. **An empty box is the correct record of an unevaluated thing**, and the
[portfolio rules](../PORTFOLIO.md#validation-checkboxes) already say so.

---

## What to write down

Tick the checklist rows you personally exercised, initialled and dated, in
[iam.md](iam.md#evaluation-checklist). Anything that surprised you goes as a note
on that candidate's portfolio page, in your own words — the notes that have been
most useful so far are the ones quoted verbatim rather than summarised.

Two things are worth recording even though no checklist row asks for them:

- **How long the twin took to create**, per system. Account lifecycle is a
  requirement, and the co-op will do this many times.
- **Whether you could tell it had worked.** That is the low-skill-threshold test,
  and it is the one thing an administrator cannot judge from the admin console.
