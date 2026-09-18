# Keycloak

[Portfolio index](../PORTFOLIO.md), candidate for [IAM](../needs/iam.md)

| | |
|---|---|
| State | Proposed |
| Repo | **Ready** [stacks/keycloak](../../stacks/keycloak) |
| Verdict | EVAL |

## Notes

---

Stack added for the IAM evaluation agreed in the 2026-09-16 meeting. Not deployed yet. Worth knowing before anyone tries the old docs: 26.x renamed the bootstrap admin variables, so KEYCLOAK_ADMIN and KEYCLOAK_ADMIN_PASSWORD are silently ignored and the instance comes up with no admin and no error. The heap is capped explicitly because the JVM sizes itself against the host RAM rather than the container limit, which on a shared node means it grows past whatever ceiling Swarm declares. - Jon Pohlner 2026-09-16
