# OpenAM (Open Identity Platform)

IAM candidate. Evaluation criteria: [docs/needs/iam.md](../../docs/needs/iam.md).

## What is not obvious, and this one has the most of it

**It is served from a Tomcat context path, not the domain root.** The console is at
`https://<domain>/auth`, not `https://<domain>/`. A bare root request returns a Tomcat
404, which reads like a broken deploy.

**Configuration lives in LDAP, not SQL.** OpenAM stores its own config in a directory
server; this stack pairs it with OpenDJ, the platform's own. The embedded alternative
puts config inside the application container, where a redeploy destroys it.

**First boot needs a configurator step that this compose does not perform.** OpenAM
ships unconfigured and expects either the web wizard at first visit or an
`Amster`/`configurator` run. Until that is done the container is up and healthy while
the service is unusable. **This is the one candidate on the shortlist that is not
fully declarative**, and that is itself an evaluation finding rather than a gap to
paper over.

**It is the largest image of the four** at 567 MB, against 174 MB for its directory
server.

`CATALINA_OPTS` caps the heap for the same reason Keycloak's does: the JVM otherwise
sizes itself against the host.
