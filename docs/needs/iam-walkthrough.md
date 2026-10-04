# IAM: walking the four candidates

[Needs index](../NEEDS.md) · [IAM need and checklist](iam.md)

Companion to the [evaluation checklist](iam.md#evaluation-checklist).

The copy evaluators use, and where their notes go, is a page in the IAM Evaluation collective, open to every co-op account:

https://cloud.chattanooga.digital/apps/collectives/IAM-Evaluation-5/IAM-evaluation-walking-the-four-candidates-3198

This file is the repo copy. If the two differ, the collective is what the evaluation ran against.

## Accounts

Each evaluator holds two accounts per system: the administrator account already issued, and a least-privilege account you create, named `<username>-test` in lower case, for example `wroush-test`. Use an address you receive mail at, because much of what is evaluated arrives by mail. `you+test@example.org` works on every mail system the co-op runs.

The target is ten accounts per system, then more. Invite other co-op members as beta testers; they keep their ordinary names.

Create the least-privilege account first: every requirement in the checklist is experienced by a non-administrator. Do routine browsing as it. If that is awkward on a product, that is a finding about the product.

Least privilege, as measured on 2026-09-22 for an account nobody has granted anything:

| | A least-privilege account | How to confirm |
|---|---|---|
| Keycloak | holds only `default-roles-master`, not the `admin` realm role | opens the account console, not `/admin/master/console/` |
| Authentik | belongs to no group | no Admin interface link after login |
| Zitadel | holds no `IAM_OWNER` and no `ORG_OWNER` membership | the console loads with its management sections absent |
| OpenAM | is a plain entry under `ou=people` with no delegation privilege | no Realms navigation after login |

---

## Keycloak

Sign in at `https://keycloak.staging.chattanooga.digital/admin/master/console/` with your short username. All five hold the `admin` realm role on `master`.

1. Create the account: *Users*, *Add user*. Username `<you>-test`, an email, Email verified off. Then *Credentials*, *Set password* with Temporary on, or *Credential Reset* with the email action so no password is chosen for them.
2. Confirm it is powerless: in a private window sign in at `https://keycloak.staging.chattanooga.digital/realms/master/account/`, then try `/admin/master/console/`. It must refuse.
3. Invite a beta tester: *Add user*, then *Credential Reset* with the Update Password action.
4. Judge: after a reset, is it clear it worked?

## Authentik

Sign in at `https://authentik.staging.chattanooga.digital/`, then open Admin interface from the user menu or go to `https://authentik.staging.chattanooga.digital/if/admin/`.

Admin comes from the `Co-op Admins` group (`is_superuser`). Authentik has no per-user admin flag.

1. Create the account: *Directory*, *Users*, *Create*. Username `<you>-test`, a real email, no group.
2. Confirm it is powerless: in a private window sign in as it. No Admin interface entry, and `/if/admin/` refuses.
3. Invite a beta tester: create the user, then *Create recovery link* on the user, or have them use the forgotten-password route on the login page.
4. Judge: whether a login is demanded twice after a reset, and whether anything you need sits behind the `enterprise/` licence.

## Zitadel

Sign in at `https://zitadel.staging.chattanooga.digital/ui/console` with your email address as the login name.

1. Create the account: *Users*, *New*. Zitadel composes the login name, and that is what signs in. Grant no manager role: do not add it under *Organization*, *Members*.
2. Confirm it is powerless: in a private window sign in with its full login name. The console loads with nothing to manage.
3. Invite a beta tester: create the user and let Zitadel send the initial mail.
4. Judge: Zitadel mails a confirmation when a password changes and sends you to a second-factor screen on the next login. Is that reassuring or an obstacle for a non-technical member?

## OpenAM

No evaluator can administer OpenAM. Measured 2026-09-22: the five evaluator accounts are plain entries under `ou=people` with no delegation privilege, `ou=groups` is empty, and the `amadmin` credential is not in the stack environment or any secret store. The stack environment holds only `DIRECTORY_PASSWORD`, which is OpenDJ's Directory Manager.

The steps above cannot be run until that changes. Checklist rows that need an administrator stay empty for OpenAM.

---

## What to write down

Tick the checklist rows you exercised, with initials and date, in [iam.md](iam.md#evaluation-checklist). Put anything that surprised you on the candidate's portfolio page, quoted verbatim.

Also record, per system, how long creating the account took and whether you could tell it had worked.
