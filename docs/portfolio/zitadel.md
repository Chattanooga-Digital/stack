# Zitadel

[Portfolio index](../PORTFOLIO.md), candidate for [IAM](../needs/iam.md)

| | |
|---|---|
| State | Proposed |
| Repo | **Ready** [stacks/zitadel](../../stacks/zitadel) |
| Verdict | EVAL |

Identity provider with OIDC, SAML and a gRPC management API. Go, multi-tenant by design.

## Notes

---

Stack added for the IAM evaluation agreed in the 2026-09-16 meeting. Not deployed yet. Two things would have cost an afternoon each if they were not written down: the master key must be exactly 32 characters or it refuses to start, and it cannot be rotated afterwards without re-encrypting every stored secret; and Traefik has to speak h2c to it, because the management API is gRPC-Web, so without that the console loads and every API call fails in a way that looks like a permissions problem. - Jon Pohlner 2026-09-16
