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

## It ignores the directory's own must-change-password flag

Measured 2026-09-18, and worth knowing before anyone counts on it. OpenDJ supports
`force-change-on-reset`, and with it on, an administrative password reset does set
`pwdReset: true` on the entry:

```
dn: uid=<user>,ou=people,dc=openam,dc=example,dc=org
pwdReset: true
```

**OpenAM signs that user straight in anyway.** No prompt, no error, a session token
first time. The reason is the chain its own configurator builds: realm `/` gets
`ldapService` containing a single **`DataStore`** module, and DataStore authenticates
against the identity store without processing the LDAP password-policy response
controls that carry the flag. The **`LDAP`** module is the one that reads them.

So a forced password change here is a change to the **authentication chain**, not a
per-user attribute. That is a real difference from the other three: Keycloak takes
`temporary: true` on the password and Zitadel takes `changeRequired: true`, both
per-user and both one field. Authentik has no per-user mechanism either, only a
password-expiry policy measured in days.

`force-change-on-reset` is left **on** in this stack's directory so the flag is set and
the gap stays visible rather than looking like nobody tried.

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
