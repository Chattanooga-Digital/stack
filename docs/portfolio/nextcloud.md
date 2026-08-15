# Nextcloud

[Portfolio index](../PORTFOLIO.md)

| | |
|---|---|
| State | Production |
| Repo | [stacks/nextcloud](../../stacks/nextcloud), proposed in [#1](https://github.com/Chattanooga-Digital/stack/pull/1) |
| Verdict | Go |

Old image runs Eduity. The new configuration is built and live at
`cloud.chattanooga.digital` since 2026-08-11, Talk since 2026-08-12. Not
all-in-one, so nothing mounts the Docker socket.

## Validation

- [x] Collabora set up and configured (built-in CODE backend)
- [x] Easy to deploy — production was torn down to bare volumes and rebuilt from
      the recipe on 2026-08-15. It came back with all 14 apps, its accounts and a
      working Talk config, with no hand steps.
- [ ] Talk works fine behind load balancer — **not signed off.** Signaling runs
      behind Traefik and publishes no host port, and the relay on 3478 answers a
      STUN binding request on both `turn.chattanooga.digital` and
      `turn.eduity.net`. But nobody has made a cross-network call yet, so this
      stays unticked until a human does. Worth knowing: the relay sees the
      overlay address rather than the client's, so every call is relayed rather
      than peer to peer.

## Notes

---
Def my #1 for proving our usefulness, probably one of the easier ones to deploy, we use it at RoushTech (we don't use Talk/docs though), it has *a lot* of value for us being able to control our file hosting. I'm somewhat hesitant about Talk (not the best experience using it so far), real-time support is very tacked on the side (thanks PHP), there's some things we cannot offer due to security concerns (all-in-one container management), but the original point still stands - William Roush 2026-08-10

---
