# PatchMon

[PatchMon](https://github.com/PatchMon/PatchMon), OS package monitoring and
patching for the nodes. One server behind Traefik with its own Postgres and Redis.

## First deploy

The first visitor to `https://${DOMAIN}` creates the superadmin. Do it as soon as
the stack is up.

## Agents

Agents are not Swarm services. Each node runs the PatchMon agent as a host
service, installed with the command PatchMon generates under Hosts, Add Host.
It runs package installs as root, so it has to live on the host, not in a
container. Agents connect out to `https://${DOMAIN}` over a WebSocket; no
inbound ports open on the node.

## Left out from upstream

Upstream's compose ships a `guacd` sidecar for in-browser RDP to Windows hosts.
It shares the server's network namespace, which Swarm cannot do, and we have no
Windows hosts.
