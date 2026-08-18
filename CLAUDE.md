# stacks

Docker Swarm stacks deployed by Portainer from this repo. Read
[docs/CONVENTIONS.md](docs/CONVENTIONS.md) before changing or adding one.

Run `./scripts/validate.sh` after touching any compose file or `.env.example`.

## Writing

Every line in this repo is context for every future reader, human or AI. Noise
compounds, so terse wins everywhere: comments, docs, commit messages.

Write as the developer, to a developer. No AI tells: no em dashes, no
"not X, but Y" framing, no ALL-CAPS warnings, no emphasis theater.

A finding from exploring or debugging goes to the developer in conversation and
stops there. It becomes a comment or doc line only when they say so. If the
developer doesn't understand something, explain it to them in the session; do
not park the explanation in a markdown file.

## Comments

Terse or absent. A variable name plus its value explains itself, so annotating
each one is noise. This applies to `docker-compose.yml`, `.env.example`, and the
READMEs equally.

Comment only what bites: a Portainer trap, an upstream typo you have to match, a
value that is dangerous to change, a credential that looks required but is
ignored. Never restate the variable name, never explain what a standard field
does, no section banners beyond the REQUIRED and OPTIONAL dividers.

State the constraint, not its history. Nobody needs to read about the mistake
that was made once, the wrong variable someone set, or what upstream gets wrong
and why. The file already has the right value in it. Exception: a migration
someone still has to carry out, which has to name the thing being migrated from.

No dates, people, tenants, or other repos in comments. Who asked for something
and when belongs in the PR.

## Documentation

A README is the contract for deploying the stack. If a variable is not in
`.env.example`, the README does not mention it.

An explanation lives as close to what it explains as practical: script behavior
in the script, a compose trap at the line it guards, never duplicated into a
README.

## Shape

No fallbacks for mechanisms this repo does not use. No guards around operations
that are already idempotent. A value that must agree in two places is one
variable referenced twice. Shell beyond a few lines is a script file, not an
inline `command:` block.
