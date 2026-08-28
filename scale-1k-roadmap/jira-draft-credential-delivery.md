# Draft: credential delivery for locally-generated admin passwords

## Summary
AF - No delivery channel for a recipe-generated admin password not derived from ROOT_PASSWORD

## Description
Today a recipe has exactly two ways to get a customer-facing credential to
the customer: `generated_from: "<algo>:ROOT_PASSWORD"` (they already know
this value — it's their own server password) or Traefik `basic_auth: true`
(same). Neither works for an app whose admin account needs its own,
independently generated password — `install.sh` can generate the value
fine (`openssl rand ...`), but there is no mechanism anywhere in `af-api`
to hand that value back to the customer afterwards. It's written to disk
and is then permanently unreachable.

Found by auditing the 240-recipe MVP batch: 12 recipes hit this exactly —
`classicpress`, `homehub`, `joomla`, `limesurvey`, `onedev`,
`paperless-ngx`, `pihole`, `razzia`, `redaxo`, `tududi`, `wg-easy`,
`wintercms`. Each ships an admin login the customer can never learn. All
currently `enabled: false`, so no live customer is affected — but none of
the 12 are shippable as authored.

`tududi` additionally hits a related but distinct gap (separate ticket):
its app hashes the password itself, so it needs the *raw* root password,
not a pre-hashed `generated_from` value — `generated_from` can only ever
emit an already-hashed string.

## Acceptance Criteria
- A new delivery mechanism for a `type: password` parameter with no
  `generated_from`: the install-time-generated value must reach the
  customer somehow (e.g. surfaced via the AF UI/API after first boot, or
  emailed/shown in a post-install summary — implementation choice is
  API team's call, this ticket is the "no channel exists at all" gap).
- `rfc/001-recipe-schema.md` documents the new field/mechanism once
  implemented.
- Add a lint check (script sketched, not yet in CI) that flags any
  `type: password` parameter with no `generated_from` and no covering
  `basic_auth: true` and no external-input phrasing in its description —
  catches this class going forward instead of relying on manual audit.
- Out of scope: fixing the 12 flagged recipes themselves (follow-up once
  the mechanism exists) and `tududi`'s separate raw-password-passthrough
  gap (separate ticket).
