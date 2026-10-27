# Beszel

[Beszel](https://github.com/henrygd/beszel), host and container metrics with
alerts. One hub behind Traefik, and one agent on every node.

## First deploy

The agent's credentials come from the hub, so this takes two deploys.

1. Deploy with `AGENT_KEY` and `AGENT_TOKEN` blank. Agents restart-loop until
   they are set.
2. Open the hub and create the admin account.
3. Under Settings, Tokens & Fingerprints, copy the public key into `AGENT_KEY`.
   Enable the universal token, switch it to permanent, and copy it into
   `AGENT_TOKEN`. The token in the Add System dialog belongs to that one
   system and gets a 401 from every other agent.
4. Redeploy. Each node registers itself under its Swarm hostname.

An ephemeral universal token expires after an hour or on hub restart, and
agents that start after that, including on new nodes, cannot register.

## Agents

The agent is `mode: global` on the host network, so it reports the node's own
interfaces. The host network cannot reach an overlay, so agents connect out to
`https://${DOMAIN}` over a WebSocket through Traefik, not to the hub by service
name.

`beszel_agent_data` holds each agent's fingerprint on its node. Losing it makes
that node register again as a new system.
