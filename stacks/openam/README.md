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

### Trap 2 — an external user store needs OpenAM's schema loaded into it

**This is the one that looks like a platform incompatibility and is not.** The
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

Only ONE credential for this stack is ours to hold: the bootstrap admin in
`ADMIN_PASSWORD`, which exists to configure the system and nothing else. Real people
are added by creating the account and letting the system send them a set-password
link. We never learn their password, so there is nothing for us to store, leak, or be
asked to rotate.

**Mail is configured in the application, not here.** Unlike Authentik and Zitadel,
this one takes no SMTP environment variables — it is set in the admin console after
first boot. That is a manual step, and until it is done every invitation and every
password reset **fails silently**. Gancio sat in exactly that state from 4 September
with nobody noticing, so check it deliberately rather than assuming.

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
```

**Accounts** — five entries under `ou=people,<basedn>`: `glaudeman`, `azahorscak`,
`turtlewolfe`, `raitchison`, `wroush`, all `inetUserStatus: Active`, no group
membership and no delegation privilege. `ou=groups` exists and is empty.

**Directory password policy** — `ds-cfg-force-change-on-reset: true`, with
`ds-cfg-password-history-count: 0` and `ds-cfg-password-history-duration: 0 seconds`.

## 🔴 Nobody can administer this instance, and the way back has a cost

`amadmin`'s password was set by hand when the instance was configured on 2026-09-18
and was never written into the stack environment or any secret store. The stack
environment carries only `DIRECTORY_PASSWORD`, which is OpenDJ's Directory Manager
and is **not** `amadmin`. REST authentication for `amadmin` also needs
`?authIndexType=service&authIndexValue=ldapService`; the plain endpoint answers
*"Authentication Module Denied"*, which reads like a bad password and is a wrong
chain. **Do not guess at it — OpenAM has account lockout.**

Two ways back, and they are not equivalent:

1. **Reset `amadmin` in the config store over LDAP.** Fast, keeps every account and
   all of the configuration above. But it is a direct write to an identity
   product's own credential store, which is the class of change this project has
   agreed not to make on supported systems, and it leaves the build no more
   reproducible than it is today.
2. **Rebuild with the credential in the environment.** Destroys the config store,
   the five accounts and everything in the section above, and requires the
   post-install script that does not yet exist. It ends with an instance that can be
   rebuilt again.

**Recommended: (2), and the reason is the evaluation rather than the tidying.**
OpenAM is a live candidate, which means we might run it. A candidate we cannot
rebuild from source is not one we can responsibly operate, so making the rebuild
work is *part of evaluating it* rather than a chore beside it. The section above
exists so that rebuild is faithful.

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

A rebuild needs, in order: `OPENAM_ADMIN_PASSWORD` added to the stack environment
and both `.env.example` files; the configurator run from that variable; the five
accounts created; the chain and realm settings above applied with `ssoadm`; the
self-service and mail settings applied; `ds-cfg-force-change-on-reset` set on
OpenDJ. Note that `ssoadm`'s password file must be mode **400**, not 600.

