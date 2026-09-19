# Authentik

[Portfolio index](../PORTFOLIO.md), candidate for [IAM](../needs/iam.md)

| | |
|---|---|
| State | Proposed |
| Repo | **Ready** [stacks/authentik](../../stacks/authentik) |
| Verdict | EVAL |

Identity provider with OIDC, SAML, LDAP and forward-auth outposts. Python and Go.

## Notes

---

Stack added for the IAM evaluation agreed in the 2026-09-16 meeting. Not deployed yet. The thing that stands out from writing it: Authentik needs four containers rather than two, because the worker is not optional - migrations, outposts and scheduled tasks all run there, and without it the server starts, serves a login page and never finishes setting up. That makes it the most expensive candidate on the shortlist to run, which matters given chadig-02 already declares more memory than it has. - Jon Pohlner 2026-09-16
