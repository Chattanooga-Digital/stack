# OpenAM

IAM candidate. Criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

The console is at `https://<domain>/openam`. The domain root returns a Tomcat 404.

## Bootstrap

OpenAM ships unconfigured, so the container is healthy while the service is unusable.
Two one-shot services set it up on every deploy and are safe to re-run:

- `dj-prep` loads the base entry, OpenAM's schema and the password policy into OpenDJ.
- `post-install` runs the configurator, then sets the realm auth chain, self-service,
  mail, accounts and the admin group.

Each ends with `opendj prep complete.` or `post-install complete.`, or names what
failed. The configurator itself fails with a bare `error code :500`; the cause is in
`/usr/openam/config/openam/debug/IdRepo`.

## Sign-in

`amadmin` signs in at `/openam/XUI/?service=ldapService#login/`. The plain
`/openam/XUI/#login/` fails for it. REST needs
`?authIndexType=service&authIndexValue=ldapService`, and without it the answer is
`Authentication Module Denied`, which looks like a wrong password. OpenAM locks accounts
out, so do not guess.

`DIRECTORY_PASSWORD` is OpenDJ's Directory Manager password.

Passwords an administrator sets must be changed at first login. A self-service reset
then demands a second change, because OpenAM sets the password by binding as the
administrator and the directory cannot tell that from an admin reset.

## Accounts and mail

`post-install` creates the `OPENAM_USERS` accounts with random passwords nobody is told,
and mails no one. People set a password through self-service reset.

OpenAM's mail service has no STARTTLS, so `SMTP_PORT` defaults to 465. With
`SMTP_PASSWORD` empty the mail phase is skipped, and resets fail without an error.

## Schema

`schema/` holds OpenAM's LDIF files, extracted unchanged from the WAR in the deployed
image. The images carry no tool to unpack it, so the files are vendored instead of
extracted at deploy time. `SHA256SUMS` records each file, and `dj-prep` refuses to run
when `schema/VERSION` differs from `OPENAM_VERSION`.

On an OpenAM upgrade, re-extract from the new image and rename the
`openam_schema_<version>_*` config names in `docker-compose.yml`:

```sh
IMG=openidentityplatform/openam:<version>
cid=$(docker create "$IMG") && docker cp "$cid:/usr/local/tomcat/webapps/openam.war" /tmp/ && docker rm "$cid"
cd stacks/openam/schema
for f in user_schema dashboard deviceprint kba oathdevices pushdevices userinit; do
  unzip -p /tmp/openam.war "WEB-INF/template/ldif/opendj/opendj_$f.ldif" > "opendj_$f.ldif"
done
echo <version> > VERSION && sha256sum *.ldif > SHA256SUMS
```

## Rebuild

A partially configured instance cannot be repaired in place. Scale the services to zero,
remove the exited task containers (they pin the volumes, and `DELETE /volumes/<name>`
answers 409 otherwise), delete `openam-config` (OpenDJ's data), `openam-home` and
`openam-ldif`, then redeploy. A redeploy onto existing volumes is safe.
