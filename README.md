# 1Password session cookies

Agent skill for storing **browser session cookies in 1Password**, fetching them
with a service account, and injecting them into Chrome or Playwright.

Cookies stay out of git. The vault is the source of truth.

This is an unofficial community skill. It is not affiliated with, endorsed by,
or supported by 1Password / AgileBits Inc. “1Password” is a trademark of
AgileBits Inc.

## Install

After this repository is public:

```bash
npx skills add alreshi/1password-cookies
```

Until then, clone it and copy the skill into your agent:

```bash
git clone git@github.com:alreshi/1password-cookies.git
# Cursor (personal, all projects)
cp -R 1password-cookies ~/.cursor/skills/1password-cookies
```

Claude Code, Codex, and other Agent Skills clients look for a root `SKILL.md`
in the usual skill directories (`.cursor/skills/`, `.claude/skills/`,
`.agents/skills/`, and so on).

## Requirements

| Step | Needs |
|------|--------|
| Push JSON → 1Password | [1Password CLI](https://developer.1password.com/docs/cli) (`op`), Python 3, macOS or Linux |
| Fetch at runtime | Node.js 18+, [`@1password/sdk`](https://www.npmjs.com/package/@1password/sdk), a service-account token |
| Inject into a browser | `puppeteer-core` or Playwright and a real Chrome install |

This skill is **not** the [1Password Environments](https://developer.1password.com/docs/environments) MCP (`.env` mounts). Do not store cookie JSON as Environment variables.

## What the agent does

1. Export cookies from Chrome (Cookie-Editor / EditThisCookie) as a JSON **array**.
2. Upsert **one** `API_CREDENTIAL` item. Each cookie is a concealed field whose value is the **full cookie object** (name, domain, path, expiry).
3. Unattended apps read the item with `@1password/sdk`.
4. Browser automation injects cookies **per origin** (`goto` the origin, then `setCookie`).

Human-facing details: [SKILL.md](SKILL.md) (for agents) and [references/REFERENCE.md](references/REFERENCE.md).

```bash
bash scripts/sync-cookies.sh \
  --vault YourVault \
  --title "example.com cookies" \
  --json ./examples/example.com.cookies.json --section app:example.com \
  --dry-run
```

`--dry-run` prints counts only. Never pass cookie values as `op` CLI flags.

## Security

Session cookies are equivalent to being logged in. Treat JSON exports, vault
items, and service-account tokens as production secrets.

- Gitignore live cookie exports. Only [examples/example.com.cookies.json](examples/example.com.cookies.json) is a fake sample.
- Log names, counts, and booleans — never values, `cookieHeader`, or tokens.
- Do not edit 1Password items titled `Service Account Auth Token: …`.
- Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## Making this repository public

The GitHub repo starts **private** so you can review it. When you are ready:

1. Confirm no real cookies, tokens, vault ids, or emails landed in git (`git log -p`).
2. GitHub → Settings → General → Danger zone → Change repository visibility → Public.
3. Create a release: `gh release create v1.0.0 --generate-notes`.
4. Add topics: `agent-skill`, `1password`, `cookies`, `cursor`, `claude-code`.
5. Install once so [skills.sh](https://skills.sh) can pick it up: `npx skills add alreshi/1password-cookies`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to send changes.

## License

[MIT](LICENSE) © Mohammed Alreshi
