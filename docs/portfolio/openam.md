# OpenAM (Open Identity Platform)

[Portfolio index](../PORTFOLIO.md), candidate for [IAM](../needs/iam.md)

| | |
|---|---|
| State | Proposed |
| Repo | **Ready** [stacks/openam](../../stacks/openam) |
| Verdict | EVAL |

Community fork of ForgeRock OpenAM. OIDC, SAML, and a policy agent ecosystem. Java on Tomcat.

## Notes

---

Stack added for the IAM evaluation agreed in the 2026-09-16 meeting. Not deployed yet. This is the one candidate of the four that is not fully declarative, and I would rather record that as a finding than hide it: OpenAM ships unconfigured and expects a web wizard or an Amster run on first boot, so the container is up and healthy while the service is unusable. It is also served from a Tomcat context path rather than the domain root, so a bare request to the domain returns a 404 that reads like a broken deploy, and it keeps its configuration in LDAP rather than SQL. Largest image of the four at 567 MB. - Jon Pohlner 2026-09-16
