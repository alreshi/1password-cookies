# Contributing

Thanks for improving this skill. It follows the [Agent Skills](https://agentskills.io/specification) format (`SKILL.md` + optional `scripts/` and `references/`).

## Ground rules

- Do **not** commit cookie JSON, `.env` files, service-account tokens, vault ids, or item ids from a real vault.
- Do **not** paste secret values into issues, pull requests, or chat logs.
- Keep `SKILL.md` under 500 lines. Put detail in `references/`.
- Scripts must send secrets through a temp `--template` (mode `0600`), never as process arguments.
- Match existing terminology: *item*, *section*, *concealed field*, *origin*, *inject*.

## Development

```bash
bash scripts/sync-cookies.sh --help
node --check scripts/fetch-session.js
```

`--dry-run` against [examples/example.com.cookies.json](examples/example.com.cookies.json) is the safe local check. It still needs `op` signed in if you point at a real vault; prefer `--dry-run`.

## Pull requests

1. Fork and branch from `main`.
2. Describe *why* the change exists in the PR body.
3. Update [CHANGELOG.md](CHANGELOG.md) under `Unreleased` (or a new version) when behavior changes.
4. Keep the MIT license headers intact.

By contributing, you agree that your work is licensed under the [MIT License](LICENSE).
