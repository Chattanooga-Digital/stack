# stacks

Docker Swarm stacks deployed by Portainer from this repo. Read
[docs/CONVENTIONS.md](docs/CONVENTIONS.md) before changing or adding one.

Run `./scripts/validate.sh` after touching any compose file or `.env.example`.

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
