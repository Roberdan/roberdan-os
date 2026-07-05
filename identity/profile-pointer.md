# profile-pointer — where the confidential dossier lives

The real, confidential operator data (clients, deals, people, real names) is **never in
this repo**. It lives local-only, gitignored, outside git history and outside every bundle:

```
$RDA_HOME/private/roberto-profile.md      # default: ~/.roberdan-os/private/roberto-profile.md
```

- The twin agent ([`agents/roberdan-twin.md`](../agents/roberdan-twin.md)) reads it at runtime **if present**.
- **If absent**, the twin degrades cleanly: style-only operation, marked `[placeholder]`
  for every name/detail it would need from the dossier. It never invents.
- Install it on a new machine with `bin/bootstrap.sh --dossier /path/to/profile.md`
  (copied with mode 600).
- The privacy gate is [`test/leak-check.sh`](../test/leak-check.sh) (denylist in
  `private/.denylist`, local-only) — see `AGENTS.md § Privacy`.

Forkers: your dossier goes in `$RDA_HOME/private/` (set `RDA_HOME` to e.g. `~/.jane-os`),
and you write your own `private/.denylist`.
