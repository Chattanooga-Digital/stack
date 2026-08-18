# TURN

One [eturnal](https://eturnal.net) shared by every stack that needs WebRTC
relaying. TURN holds no per-tenant state: a consumer is anything that knows
`TURN_SECRET` and can reach the port. [nextcloud](../nextcloud) is the first
one, and its README carries the `occ` side of the wiring.

## Host networking

This is the only stack in the repo that joins the predefined `host` network
instead of publishing ports, because published ports cannot work here. Every
concurrent relay allocation binds its own UDP port out of
`RELAY_MIN_PORT`-`RELAY_MAX_PORT`, and Swarm forwards only the ports named in a
`ports:` block, so a client handed a relay candidate on port 51234 would be
talking to nothing. Host netns also means eturnal sees real client addresses.

Consequences worth knowing before deploying it:

- One instance per node. It binds `TURN_PORT` on the host directly, so a second
  copy on the same node fails to start, and nothing else may hold 3478.
- No Traefik, no `INSTANCE_NAME`. Traefik routes HTTP, and TURN is not HTTP.
- The node's own firewall has to allow `TURN_PORT` on udp and tcp, plus the
  relay range on udp.
- DNS for the TURN hostname is an A record straight at the node, not at
  anything Traefik terminates.

Erlang's distribution listener binds 127.0.0.1 only, so host netns does not
expose it.

## PEER_WHITELIST

`blacklist_peers: recommended` refuses relaying to private ranges, which is what
keeps this from being an open door into the internal network. The SFU on the
other end of a call is on such a range, so its address has to be whitelisted or
media toward it is refused while everything else looks healthy.

The default `10.0.0.0/8` covers an SFU on the Swarm overlay of the same node.
An instance on another node reaches us from that node's address instead, so add
it.

## The secret is shared

Anyone holding `TURN_SECRET` can mint credentials on this server, so it is one
trust boundary across every consumer, not one per instance. Changing it cuts
live calls and every consumer has to change with it in the same window.

## Checking it

```
docker exec $(docker ps -qf name=turn) eturnalctl info
docker exec $(docker ps -qf name=turn) eturnalctl sessions
```

`eturnalctl credentials` prints a working username and password pair for
testing against [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/),
which should report a `relay` candidate.
