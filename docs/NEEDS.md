# Needs

Capabilities we have decided we want but have not picked a platform for. One
page each under [docs/needs/](needs/), notes on the page itself.

## Key

**Status:** `Open` (candidates under evaluation), `Decided` (a platform was
picked and has a portfolio page), `Dropped` (we stopped wanting it).

**Decision:** the platform picked, empty until there is one.

## How a need gets decided

1. Put the requirements (each must pass) and the nice-to-haves on the need page. Judge candidates against it, not their own feature lists.
2. Read what already exists: licence, release history, advisories, reviews. A candidate that fails a requirement on paper stops here, with the reason on the page.
3. Deploy the shortlist to staging, one stack each under `stacks/`, with a [portfolio page](PORTFOLIO.md) at `Proposed`. A candidate that cannot be deployed from a stack file is a finding on its page.
4. Evaluate by use. The need page carries a checklist, one column per candidate. Evaluators tick what they verified with initials and date, per the [portfolio rules](PORTFOLIO.md#validation-checkboxes). An empty box is unchecked.
5. Decide. Record the platform in the Decision column and set the need to `Decided`. The winner's portfolio page moves to `Pilot`; the others stay as the record.
6. The ticked requirements become the winner's Validation list.

## Needs

| Need | Status | Decision |
|---|---|---|
| [IAM](needs/iam.md) | Open | |
| [Source control](needs/source-control.md) | Open | |

