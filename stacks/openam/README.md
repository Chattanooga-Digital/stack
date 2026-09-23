# OpenAM (Open Identity Platform)

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## What is not obvious, and this one has the most of it

**It is served from a Tomcat context path, not the domain root.** The console is at
`https://<domain>/openam`, not `https://<domain>/`. A bare root request returns a
Tomcat 404, which reads like a broken deploy. The context path comes from the image's
`OPENAM_PATH` (default `openam`) — it is not `/auth`, which is Keycloak's.

**Configuration lives in LDAP, not SQL.** OpenAM stores its own config in a directory
server; this stack pairs it with OpenDJ, the platform's own. The embedded alternative
puts config inside the application container, where a redeploy destroys it.

**First boot needs a configurator step that this compose does not perform.** OpenAM
ships unconfigured. Until that is done the container is up and healthy while the
service is unusable. **This is the one candidate on the shortlist that is not fully
declarative**, and that is itself an evaluation finding rather than a gap to paper
over.

**It is the largest image of the four** at 567 MB, against 174 MB for its directory
server.

`CATALINA_OPTS` caps the heap for the same reason Keycloak's does: the JVM otherwise
sizes itself against the host.

## Configuring it — the supported path, and the two traps in it

Use the **configurator tool that ships inside the image**, not the `/config/configurator`
servlet. Hand-POSTing form fields to that servlet is not a supported surface: it accepts
a half-valid parameter set, returns 500, and names neither the rejected field nor the
cause.

```
/usr/openam/ssoconfiguratortools/openam-configurator-tool-15.0.3.jar
```

Write a properties file and run `java -jar openam-configurator-tool-<version>.jar
--file <file>` from that directory. Two parameter details cost a day each:

- The licence key is **`ACCEPT_LICENSES=true`**. `acceptLicense=true` is silently
  ignored, so the run fails later and for an unrelated-looking reason.
- **Leave `AM_ENC_KEY` empty.** The tool generates one. "Encryption key must be
  provided" comes from the servlet path, not from the tool.

`AMLDAPUSERPASSWD` has **no `_CONFIRM` twin**, and there is no `ADMIN_CONFIRM_PWD`.

### Trap 1 — this OpenDJ advertises the suffix but never creates the base entry

`dc=openam,dc=example,dc=org` appears as a naming context while an authenticated
`ldapsearch` for it returns `32 (No Such Entry)`. With `DATA_STORE=dirServer` the base
entry must exist first, so add it before configuring:

```ldif
dn: dc=openam,dc=example,dc=org
objectClass: top
objectClass: domain
dc: openam
```

The configurator reports this as `Invalid Suffix`, which names neither the cause nor
the fix.

**And the two containers under it.** The configurator writes its demo user into
`ou=people` and never creates it. The 09-18 directory backup shows `ou=people` and
`ou=groups` (plain `organizationalUnit`) created by Directory Manager 28 seconds after
the base entry and before the configurator's first write — by hand, like the base entry,
and recorded nowhere until the first fresh rebuild failed on it. That failure looks
exactly like Trap 2 below (a bare `error code :500` at "Creating demo user"); the
difference is only in `debug/IdRepo`: *"parent entry ou=people,… does not exist"*.
`dj-prep` creates the base entry, then applies OpenAM's own `opendj_userinit.ldif`
(vendored in `schema/`): both containers **and** the deny ACI described under Trap 2,
which the 09-18 directory also carries. Hand-writing the two containers — as this stack
briefly did (803a7b1) — builds a directory that works and silently lacks that ACI.

### Trap 2 — an external user store needs OpenAM's schema loaded into it

**This is the one that looks like a platform incompatibility and is not** — and the
same bare 500 also means a missing `ou=people` (above), so read `debug/IdRepo` before
deciding which. The
configurator runs all the way through registering services, configuring the system and
configuring the server instance, then fails on its very last step with a bare
`Configuration Failed. The server returned error code :500`. The real error is only in
`/usr/openam/config/openam/debug/IdRepo`:

```
ConstraintViolationException: Object Class Violation: Entry
uid=demo,ou=people,dc=openam,dc=example,dc=org violates the Directory Server schema
configuration because it contains an unknown objectclass pushDeviceProfilesContainer
```

OpenAM's demo user carries five objectclasses the stock OpenDJ does not define. The
image ships the LDIF that defines them, and loading it is the administrator's job, not
the configurator's. Apply these to the user store **before** running the configurator,
from `/usr/local/tomcat/webapps/openam/WEB-INF/template/ldif/opendj/`:

| file | what it adds |
|---|---|
| `opendj_user_schema.ldif` | the core OpenAM user schema |
| `opendj_dashboard.ldif` | `forgerock-am-dashboard-service` |
| `opendj_deviceprint.ldif` | `devicePrintProfilesContainer` |
| `opendj_kba.ldif` | `kbaInfoContainer` |
| `opendj_oathdevices.ldif` | `oathDeviceProfilesContainer` |
| `opendj_pushdevices.ldif` | `pushDeviceProfilesContainer` |
| `opendj_userinit.ldif` | `ou=people`, `ou=groups`, and the self-modification deny ACI |

`opendj_userinit.ldif` carries an `@userStoreRootSuffix@` token that must be replaced
with the root suffix before it is applied. **Prefer it over hand-writing the two
organizational units** — creating them by hand works and silently omits the ACI that
stops users editing their own account status.

Everything but `opendj_userinit.ldif` is a `cn=schema` modify, so apply with
`ldapmodify` against the LDAP port as `cn=Directory Manager`.

`opendj_user_index.ldif` is optional and performance-only; it targets `cn=config` and
carries a `@DB_NAME@` token for the backend id.

### Why it is worth writing down rather than scripting around

A partially-configured instance is not recoverable in place — the config store and
`/usr/openam` both hold state from the failed run. Start from empty volumes.
`openam-config` is **OpenDJ's** data (`/opt/opendj/data`) and `openam-home` is the
application's; both have to go. A Swarm stack stop scales services to zero and leaves
**exited** task containers holding the volumes, so `DELETE /volumes/<name>` returns
409 while `containers/json` reports nothing running. Remove the exited containers
first, and treat a 409 as "not reset" rather than retrying past it.

## The schema is vendored, per OpenAM version, in `schema/`

Trap 2 below needs OpenAM's six schema LDIFs — and its `opendj_userinit.ldif`, which is
not schema but ships beside them — loaded into OpenDJ **before** the
configurator runs. They ship only inside the WAR, under
`WEB-INF/template/ldif/opendj/`, and they are vendored here byte-identical — extracted
from the WAR of the image actually deployed,
`openidentityplatform/openam:16.1.3@sha256:b55b2567208bf99ea47537c40231b49a8fc11c93cf1f4c26e51ca026a137c5a9`.
`SHA256SUMS` records each file. All six modify `cn=schema` only and carry no `@TOKEN@`
placeholders, so they load as-is. `dj-prep` mounts them as Swarm configs and **refuses
to run if `schema/VERSION` differs from `OPENAM_VERSION`**.

Why not extract them at deploy time, measured 2026-09-23 on the 16.1.3 image: it carries
no `unzip`, `jar`, `python3`, `busybox` or `bsdtar`, and Tomcat unpacks the WAR only when
it *starts*, which a one-shot never does. A named volume over Tomcat's `webapps` would
work once and then keep serving the **old** WAR after an upgrade, because an existing
volume is never refilled from the image — the same trap `post-install.sh` guards for
`openam-home`. And the conventions forbid fetching code at deploy time.

**Why not the OpenDJ image's own bootstrap.** `run.sh` runs `bootstrap/setup.sh` on
first start, and it *can* create the base entry (`ADD_BASE_ENTRY=--addBaseEntry`) and
load LDIFs from `bootstrap/schema/`. It runs **once**, on an empty data volume, so it
can never add the schema a later OpenAM version needs; and its `bootstrap/data/` path
silently sets `allow-pre-encoded-passwords:true` on the default password policy.
`dj-prep` re-runs on every deploy and reconciles instead. For the same reason it
cannot use `dsconfig`: the tool first checks the version of a *local* installation,
and a container where `run.sh` never ran has none (`config/buildinfo` not found), so
the password policy is set with the same LDAP modify `dsconfig` would send, and read
back.

**On an OpenAM upgrade**, re-extract from the new image, then rename the
`openam_schema_<version>_*` config names in `docker-compose.yml` to match:

```sh
IMG=openidentityplatform/openam:<version>
cid=$(docker create "$IMG") && docker cp "$cid:/usr/local/tomcat/webapps/openam.war" /tmp/ && docker rm "$cid"
cd stacks/openam/schema
for f in user_schema dashboard deviceprint kba oathdevices pushdevices; do
  unzip -p /tmp/openam.war "WEB-INF/template/ldif/opendj/opendj_$f.ldif" > "opendj_$f.ldif"
done
echo <version> > VERSION && sha256sum *.ldif > SHA256SUMS
```

## One-shots must not inherit the image's healthcheck

Both images declare a `HEALTHCHECK` for their server — OpenAM probes
`localhost:8080/openam/isAlive.jsp`, OpenDJ its LDAP port. `dj-prep` and `post-install`
run those images without starting the server, so the probe fails and Swarm **kills the
task** as unhealthy: `task: non-zero exit (137): dockerexec: unhealthy container`,
measured on the first 16.1.3 rebuild. It reads like an out-of-memory kill and is not
one. Both one-shots set `healthcheck: disable: true`.

## Forcing a password change costs you the console login, and nothing says so

Measured 2026-09-18, end to end. Three facts, in the order they bite.

**1. The default chain ignores the directory.** Turn on `force-change-on-reset` in
OpenDJ and an administrative reset does set `pwdReset: true` on the entry. OpenAM signs
that user straight in regardless. Its configurator builds realm `/` with `ldapService`
containing a single **`DataStore`** module, and DataStore does not process the LDAP
password-policy response controls that carry the flag.

**2. The `LDAP` module does honour it, and it is already configured.** The instance
ships pointed at the directory with `beheraPasswordPolicySupportEnabled: true`, which is
the setting that reads those controls. Authenticating against it directly proves the
difference without changing anything:

```
authIndexType=module&authIndexValue=LDAP       -> Old Password / New Password / Confirm
authIndexType=module&authIndexValue=DataStore  -> signs straight in
```

Note the instance names are lowercase in the config API (`ldap`, `datastore`) and
capitalised when naming a module to authenticate against (`LDAP`, `DataStore`). Using
the wrong case returns `Authentication Module Not Found`, which reads like the module
does not exist.

**3. Switching to it locks `amadmin` out of the default login.** `amadmin` lives in the
configuration store, not under the user search base, so it cannot bind through the LDAP
module at all. Point the realm's organisation chain at LDAP and `amadmin` starts
failing with a bare `Authentication Failed`. A chain of `LDAP SUFFICIENT` then
`DataStore SUFFICIENT` does **not** rescue it, and is worth knowing it was tried.

The workable arrangement, which is what this instance now runs:

```
chain userLdapService = [ LDAP REQUIRED ]
iplanet-am-auth-org-config      = userLdapService   <- real users, forced change
iplanet-am-auth-admin-auth-module = ldapService     <- amadmin, still DataStore
```

`amadmin` then signs in at **`/openam/XUI/?service=ldapService#login/`**. The plain
`/openam/XUI/#login/` will fail for it, because XUI calls the organisation chain.

### Two things about applying it

**The REST config endpoint will not make this change.** `PUT` on
`/json/realms/root/realm-config/authentication` returns `Resource '' not found`, and
`PATCH` returns `Patch not supported`. Use **`ssoadm`**, which the image ships
unconfigured at `/usr/openam/ssoadmintools`; run its `setup` first. Creating the chain
itself *is* fine over REST.

**`ssoadm`'s password file must be mode 400.** At 600 it refuses with *"Password file
needs to be readonly by owner only"* — the same family of trap as a `chmod +x` on a
`mktemp` file landing at 0700.

🔴 **This configuration is NOT in the compose file**, because it is realm state inside
the configuration store rather than a container setting. A fresh deploy of this stack
comes up with the DataStore chain and no forced password change. If OpenAM is the
candidate we pick, this belongs in a scripted post-install step, not in a runbook step
somebody has to remember.

## Accounts: invite links, not passwords we choose

The only credentials for this stack that are ours to hold are the administrator's
(`OPENAM_ADMIN_PASSWORD`) and the service account it configures, which exist to run
the system and nothing else. Real people
are added by creating the account and letting the system send them a set-password
link. We never learn their password, so there is nothing for us to store, leak, or be
asked to rotate.

**Mail lives in OpenAM's config store, and `post-install` writes it there** from the
`SMTP_*` stack variables. On 2026-09-18 it was set by hand in the admin console, which
is why a rebuild would have lost it. If `SMTP_PASSWORD` is empty the phase is skipped
and says so — and until it runs, every invitation and every password reset **fails
silently**. Gancio sat in exactly that state from 4 September with nobody noticing, so
check it deliberately rather than assuming.

**An account needs a `mail` attribute to receive its link.** Self-service reset sends
to it, so `OPENAM_USERS` carries `uid,mail,Given,Surname` per person, and a record
missing a field is refused rather than half-created.

## The live instance's actual configuration, measured 2026-09-23

Everything below was read out of the OpenDJ config store, not remembered. It is the
set of things a fresh deploy does **not** get, and therefore exactly what a
post-install script has to reproduce. Password values are held in the store and are
deliberately not recorded here; the stack environment is where they belong.

**Realm authentication** — `ou=default,ou=OrganizationConfig,ou=1.0,ou=iPlanetAMAuthService,ou=services,<basedn>`

```
iplanet-am-auth-org-config        = userLdapService
iplanet-am-auth-admin-auth-module = ldapService
iplanet-am-auth-alias-attr-name   = uid
```

**The chain itself** — `ou=userLdapService,ou=Configurations,ou=default,ou=OrganizationConfig,ou=1.0,ou=iPlanetAMAuthConfiguration,ou=services,<basedn>`

```
iplanet-am-auth-configuration = <AttributeValuePair><Value>LDAP REQUIRED </Value></AttributeValuePair>
```

Three chains exist: `ldapService` (stock, and what `amadmin` uses), `amsterService`
(stock), and `userLdapService` (ours).

**Self-service password reset** — `ou=default,ou=OrganizationConfig,ou=1.0,ou=selfService,ou=services,<basedn>`

```
selfServiceForgottenPasswordEnabled                 = true
selfServiceForgottenPasswordEmailVerificationEnabled = true
selfServiceForgottenPasswordKbaEnabled              = false
selfServiceForgottenPasswordCaptchaEnabled          = false
selfServiceForgottenPasswordTokenTTL                = 86400
selfServiceEncryptionKeyPairAlias                   = selfserviceenctest
selfServiceSigningSecretKeyAlias                    = selfservicesigntest
```

**Mail** — `ou=default,ou=OrganizationConfig,ou=1.0,ou=MailServer,ou=services,<basedn>`

```
forgerockEmailServiceSMTPHostName    = smtp.resend.com
forgerockEmailServiceSMTPHostPort    = 465          <- SSL, not STARTTLS; see above
forgerockEmailServiceSMTPSSLEnabled  = SSL
forgerockEmailServiceSMTPUserName    = resend
forgerockEmailServiceSMTPFromAddress = no-reply@get.chattanooga.digital
forgerockEmailServiceSMTPSubject     = Set your password
forgerockEmailServiceSMTPMessage     = Use the link below to choose a password for your account.
```

**Both of these are services ASSIGNED to the root realm**, not only global defaults:
each has its own `ou=default,ou=OrganizationConfig` entry in the 09-18 directory,
created about 11 hours after configuration. The first record here gave the DNs but
not that, and missed the message body. `post-install` writes both places, to
reproduce 09-18; whether the realm copy is *required* has not been tested.

**Testing the reset over REST takes TWO calls, and the first sends nothing.**
`submitRequirements` with `{"input":{"queryFilter":"uid eq \"<uid>\""}}` answers
`emailValidation` / `initial` — the flow is now *asking* for a hidden
`querystringParams`, which the XUI supplies. Only the second call, with the token and
`{"input":{"querystringParams":"{}"}}`, sends the mail and answers `validateCode`.
`querystringParams` must be a **string**: an object gets a 500 whose only trace is
`debug/CoreSystem`: *"/input/querystringParams: Expecting a java.lang.String"*.
Measured 2026-09-23: stopping after the first call looks exactly like "mail is broken"
— 200, no error, no mail, nothing in the logs — and was misread that way once. The
two-call version delivered to Gmail in under a second. The mail arrives with OpenAM's
stock subject, *"Forgotten password email"*, from the self-service settings, not the
mail service's own subject.

**Accounts** — five entries under `ou=people,<basedn>`: `glaudeman`, `azahorscak`,
`turtlewolfe`, `raitchison`, `wroush`, all `inetUserStatus: Active`, each carrying
`mail`, `givenName`, `sn` and `cn`, no group membership and no delegation privilege.
`ou=groups` exists and is empty. *(The first version of this line named only the uids
and status, and the post-install written from it created accounts with no address to
send a reset link to. Re-measured from the directory backup the same day.)*

**And a sixth: `demo`.** The configurator always creates `uid=demo`, Active, with
OpenAM's documented default password `changeit`. On the 09-18 instance it was still
Active with that password unchanged since creation, and on 2026-09-23 `demo` /
`changeit` returned a session from the public URL of the fresh rebuild. `post-install`
deletes it. The line above originally said "five entries" and missed it.

**Directory password policy** — `ds-cfg-force-change-on-reset: true`, with
`ds-cfg-password-history-count: 0` and `ds-cfg-password-history-duration: 0 seconds`.

## Administering it, and rebuilding it

**`amadmin`'s password is `OPENAM_ADMIN_PASSWORD` in the stack environment**, and the
`amldapuser` service account's is `OPENAM_AMLDAPUSER_PASSWORD` — two values, so one
leak is not two. Neither is OpenDJ's Directory Manager (`DIRECTORY_PASSWORD`). REST
authentication for `amadmin` needs `?authIndexType=service&authIndexValue=ldapService`;
the plain endpoint answers *"Authentication Module Denied"*, which reads like a bad
password and is a wrong chain. **Do not guess at it — OpenAM has account lockout.**

**How it got here.** On 2026-09-18 the password was typed into the configurator by
hand and recorded nowhere, so nobody could administer the instance. Resetting it over
LDAP was rejected (a direct write to an identity product's own credential store, and
no more reproducible afterwards). Instead the stack was **rebuilt from empty volumes on
2026-09-23, on 16.1.3**, with every hand step from 09-18 moved into `dj-prep` and
`post-install`. OpenAM is a live candidate; one we cannot rebuild from source is not
one we could responsibly run, so making the rebuild work was part of evaluating it.

The first from-zero runs found these, each now handled in the scripts:

| Found | Where it is handled |
|---|---|
| Swarm killed both one-shots, exit 137, "unhealthy container" (the images' own healthchecks) | `healthcheck: disable` on both |
| `dsconfig` needs a local installation (`config/buildinfo`) the one-shot does not have | `dj-prep` uses `ldapmodify` on `cn=config`, reads it back |
| Re-sending a schema file always fails once it is loaded (`20 Attribute or Value Exists`) | `dj-prep` reconciles per definition, by OID |
| `ou=people` / `ou=groups` never created by the configurator (bare 500 at "Creating demo user") | `dj-prep` applies `opendj_userinit.ldif`: both, plus the self-modification deny ACI |
| An unconfigured OpenAM answers `isAlive.jsp` with a **302** to its setup page, never 200 | `post-install` accepts either state |
| OpenAM will not create a user with no password ("Minimum password length is 8.") | 32 random characters nobody is told, via `ssoadm -D` |
| `ssoadm show-identity` does not exist, so every account read as absent | `identity_state`: `list-identities`, three answers |
| The configurator's `demo` account, Active, password `changeit` — it logged in | `post-install` deletes it |

**To rebuild again:** scale the stack's services to zero; remove the *exited* task
containers (they pin the volumes, and `DELETE /volumes` answers 409 otherwise); delete
`openam-config`, `openam-home` and `openam-ldif`; redeploy. `dj-prep` then
`post-install` do the rest — read `post-install`'s log, it ends
`post-install complete.` or names what failed. A redeploy onto existing volumes is
safe: every phase checks before it acts, and a re-run was proven to exit 0 with
everything skipped or re-applied. The accounts come back **without anyone being
mailed** — sending people their set-password links is a separate, deliberate step.

**The admin tools ship in the image. The trap is a reused volume, not a missing
download.** Upstream's Dockerfile — 15.0.3 and 16.1.3 alike, lines 27–30 of
`openam-distribution/openam-distribution-docker/Dockerfile` — downloads
`SSOConfiguratorTools` and `SSOAdminTools` at build time and unpacks them into
`/usr/openam`. `openam-home` mounts over that path, so from inside a running
container the image's copy is invisible; but Docker fills an **empty** named volume
from the image on first mount. So a fresh `openam-home` gets the tools of the image
that first mounts it, and a **reused** one keeps the tools of whatever image created
it. Upgrading 15.0.3 → 16.1.3 while keeping the volume would run a 16.1.3 WAR against
a 15.0.3 configurator. `post-install.sh` therefore checks the configurator's version
against `OPENAM_VERSION` before it does anything, and says which volume to drop.

What the image genuinely lacks is an LDAP client — no `ldapmodify`, no `dsconfig` —
which is why the directory work lives in `dj-prep` on the OpenDJ image.

*Correction, 2026-09-23.* This section previously said the image shipped no admin
tools, that the live volume's copy had been downloaded by hand on 2026-09-18, that a
rebuild was blocked until a derived image or a REST rewrite existed, and that this
set OpenAM apart from the other three candidates. All four statements were wrong,
and were committed in d939429. The search behind them excluded `/usr/openam` — the one
path the volume masks. The live volume's tools came from the 15.0.3 image on first
mount. OpenAM, like the other three, ships as one image with its own tooling.

Note that `ssoadm`'s password file must be mode **400**, not 600.

