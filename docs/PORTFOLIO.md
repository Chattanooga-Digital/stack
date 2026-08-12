# Portfolio of record

Every platform we run, what state it is in, whether this repo can deploy it, and
what we have decided to do about it. One page each under
[docs/portfolio/](portfolio/), notes on the page itself.

- **State as of:** 2026-08-11
- **This page:** index only. The platform pages are the record.

## How to use it

Edit the platform page directly, not this index. Append your note at the bottom
of its **Notes** section under a `---` rule, ending `- Name YYYY-MM-DD`. Full
name, no backticks: a note is prose, not a stamp. Disagree in your own note,
never by rewriting someone else's.

This index carries no notes. When you change a State, Repo, or Verdict on a
platform page, update its row in [Portfolio](#portfolio) to match.

### Validation checkboxes

Every Pilot carries a **Validation** list: the things that must be true before it
stops being a pilot. Tick your own line, never someone else's.

```
- [ ] Not verified yet
- [x] Verified, by whoever initialled it `WR 2026-08-11`
```

Initials and an ISO date go in backticks at the end. No initials means nobody
verified it, so the box stays empty no matter how true it looks. If verification
needs proof, put the command or the URL on an indented line under the item.

A box means *I personally checked this*, not *someone told me* and not *the code
looks right*.

### Who signs what

Two things carry a name, and they are not the same claim.

| Signature | On | Means | When |
|---|---|---|---|
| Checkbox initials | One validation line | I verified this myself | Any time, as you verify |
| Note | One platform | My position, agreement or not | Any time |

There is no sign-off block. Git records who changed what and when, and a
signature table would only be a worse copy of it that goes stale on the next
edit.

A Pilot moves to Running when its Validation list is fully ticked. Note the
change rather than making it quietly.

## Roster

Initials used in checkboxes and Notes. Fill in your own.

| Initials | Name | Role |
|---|---|---|
| WR | William Roush | |
| | Greg | |
| | Jon | |

## Key

**State:** `Running` (it's ready for production use), `Pilot` (deployed, not yet trusted),
`Proposed` (not deployed).

**Repo:** whether we can deploy it today.

| | Meaning |
|---|---|
| Ready | Tracked in a repo, deployable |
| Blocked | Tracked, cannot deploy until something named is supplied |
| Absent | Not tracked anywhere. Deployed by hand |

**Verdict:** `Go`, `KEEP`, `FROZEN`, `EVAL` (contested or undecided, needs a
decision).

## Portfolio

| Platform | State | Repo | Verdict |
|---|---|---|---|
| [Nextcloud](portfolio/nextcloud.md) | Pilot | Blocked | Go |
| [Track](portfolio/track.md) | Running | Ready | Go |
| [CiviCRM](portfolio/civicrm.md) | Pilot | Absent | Go |
| [Mastodon](portfolio/mastodon.md) | Running | Ready | Go |
| [Discourse](portfolio/discourse.md) | Pilot | Absent | FROZEN |
| [Mailman](portfolio/mailman.md) | Running | Absent | FROZEN |
| [Drupal](portfolio/drupal.md) | Pilot | Absent | KEEP |
| [BigCapital](portfolio/bigcapital.md) | Pilot | Ready | FROZEN |
| [Hubzilla](portfolio/hubzilla.md) | Pilot | Absent | EVAL |
| [Keycloak](portfolio/keycloak.md) | Proposed | Absent | EVAL |

Adding a platform: copy the shape of an existing page into
`portfolio/<name>.md`, add a row above, and remove the name from the inventory
below.

## Everything else evaluated

This is a list of everything previous discussed at one point, add anything else discussed to this list, it needs its own pages and discussion.

### Files and collaboration

- Cal.com
- Cryptpad
- OpenProject
- Super Productivity

### Websites and CMS

- WordPress (managed)
- WooCommerce
- Silex
- Microweber, Publii, Elementor
- LinkStack

### CRM and membership

- SuiteCRM
- Tendenci

### Accounting and ERP

- Odoo
- Akaunting
- ERPNext
- Dolibarr, Frappe Books
- GnuCash

### Email

- Mailfence
- Resend
- Postfix, Dovecot
- Self-hosted mail as a product
- Listmonk
- Stalwart
- OpenLDAP, Radicale
- Mailcow
- SOGo
- Mail-in-a-box
- phpList
- Sympa
- Forward Email

### Social and community

- Friendica
- OSSN
- Hylo
- Matrix, Synapse
- Mattermost, Rocket.Chat, Element, Revolt

### Identity

- Vaultwarden
- Open Identity Platform

### Deployment, panels, orchestration

- Portainer, Traefik, MinIO, WireGuard, Docker Swarm
- Uptime Kuma
- Kubernetes, K3s, Rancher, Kubero
- Self-serve signup panel (the category)
- Coolify
- CapRover
- Co-op Cloud, Abra
- Cosmos Cloud, DevPanel, Drupal Forge, elest.io
- CloudFoundry, Stratos
- OpenStack
- Federated Computer, House of FOSS, PikaPods

### Billing and metering

- FOSSBilling
- BillRun, Freeside, WHMCS-alikes
- Prometheus

### Media, education, events

- Castopod
- Moodle
- Jitsi
- Owncast
- BigBlueButton
- OSM tile server
- Grocy

### Misc

- Hubzilla-as-docs, form builders, LinkStack-alikes, one-off floats
