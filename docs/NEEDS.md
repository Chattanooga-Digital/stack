# Needs

Capabilities we have decided we want but have not picked a platform for. One
page each under [docs/needs/](needs/), notes on the page itself.

## Key

**Status:** `Open` (candidates under evaluation), `Decided` (a platform was
picked and has a portfolio page), `Dropped` (we stopped wanting it).

**Decision:** the platform picked, empty until there is one.

## How a need gets decided

The process is this repo's structure, used in order. It came out of the
2026-09-16 IAM meeting (agenda: requirements, nice to have, candidates,
evaluation checklist) and the three evaluation guides Greg circulated on
2026-08-27, reduced to what applies to software we deploy off the shelf and
operate rather than build with. [IAM](needs/iam.md) is the first need run through
it.

1. **Say why.** The need page opens with the sponsor and the purpose, then
   *Requirements* (each must pass) and *Nice to have*. A candidate is judged
   against that page, never against its own feature list.
2. **Identify candidates and read what already exists**: licence, release
   history, advisories, other people's reviews. A candidate that fails a
   requirement on paper stops here, and the page says why.
3. **Deploy the shortlist to staging**, one stack each under `stacks/`, with a
   [portfolio page](PORTFOLIO.md) at `Proposed`. A candidate that cannot be
   deployed from a stack file is a finding, recorded on its page, not a gap to
   script around.
4. **Evaluate by use.** The need page carries an *Evaluation checklist*: the
   requirements, project health, cost to run and usability, one column per
   candidate. Evaluators tick what they personally verified, initialled and
   dated, under the [portfolio rules](PORTFOLIO.md#validation-checkboxes). An
   empty box means unchecked, and stays empty until someone checks it.
5. **Decide.** Record the platform in the *Decision* column below and set the
   need to `Decided`. The winner's portfolio page moves to `Pilot`; the others
   stay as the record of why not.
6. **Reuse the checklist.** The ticked requirements become the winner's
   *Validation* list, so the evaluation is also the deployment check.

Evidence beats assertion at every step: a value with a date and a method beside
it, or an empty box.

## Needs

| Need | Status | Decision |
|---|---|---|
| [IAM](needs/iam.md) | Open | |
| [Source control](needs/source-control.md) | Open | |

