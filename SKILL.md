---
name: 1password-cookies
description: >-
  Store browser cookie JSON in a 1Password API Credential item (one concealed
  field per cookie, full cookie object), fetch with the 1Password JS SDK and a
  service account, and inject into Chrome or Playwright. Use when syncing
  cookies to 1Password, logging a browser in from 1Password cookies, porting
  the cookie toolkit to a new site, or when the user mentions Get cookies.txt
  LOCALLY, Cookie-Editor, or EditThisCookie JSON with 1Password. Distinct from
  1Password Environments (.env mounts).
license: MIT
compatibility: >-
  Requires 1Password CLI (op) and Python 3 for cookie sync; Node.js and
  @1password/sdk for runtime fetch. macOS or Linux. Not the 1Password
  Environments MCP.
metadata:
  author: Mohammed Alreshi
  version: "1.0.0"
  tags: 1password cookies session puppeteer playwright agent-skill
---

# 1Password session cookies

Playbook for authenticated browser sessions whose cookies live in 1Password,
not in git. Read this before writing cookie sync, fetch, or inject code.
Item schema, Chrome mapping, and troubleshooting: [references/REFERENCE.md](references/REFERENCE.md).

This skill is a **session-cookie** workflow. It is not the 1Password
Environments MCP (`.env` mounts). Do not store cookie JSON as Environment
variables.

## Not done until

**Push (JSON → 1Password)**

- [ ] Cookies exported with **Get cookies.txt LOCALLY** as **JSON** (not Netscape `.txt`)
- [ ] Cookie JSON files are gitignored
- [ ] `op` is signed in and the vault exists
- [ ] Item created or updated via `--template` (never secret values on argv)
- [ ] Summary logged (counts, section names, token present/absent only)

**Fetch (app / agent runtime)**

- [ ] `OP_SERVICE_ACCOUNT_TOKEN` comes from env, never hardcoded
- [ ] Each cookie field parsed as full cookie-object JSON, with plain-value fallback
- [ ] Logs show counts / hostname / token-present — never values

**Inject (browser)**

- [ ] Cookies grouped by origin; page navigates to that origin **before** `setCookie`
- [ ] `sameSite`, `domain` / `hostOnly`, `secure` mapped (see [references/REFERENCE.md](references/REFERENCE.md))
- [ ] Cookies Chrome rejects are skipped; login is proven without dumping cookies

## Do not

- Commit cookie JSON, or paste cookie / token / `cookieHeader` values into chat
- Put secrets on process argv (`op item edit … value=secret`)
- Modify items whose title is `Service Account Auth Token: …`
- Use the 1Password Environments MCP or `.env` mounts for cookie sessions
- Log `Set-Cookie`, `Authorization`, `access_token`, or field values
- Treat a cookie field as a bare string when it is JSON (domain/path/expiry must survive)

## Architecture

1. Human exports cookies from Chrome with **Get cookies.txt LOCALLY** as a JSON **array** of cookie objects.
2. CLI (`op item create|edit --template`) upserts **one** `API_CREDENTIAL` item. Each cookie is a **concealed** field whose value is the **entire cookie object JSON**.
3. Unattended apps fetch with `@1password/sdk` and a service-account token.
4. Browser automation injects cookies **per origin**, then optionally writes an access token into `localStorage` / `sessionStorage`.

Interactive `op` is for humans (and agents with a signed-in CLI). Service-account SDK is for bots and scrapers.

## New project checklist

Copy this list and fill it in before writing code:

```
- [ ] Vault name
- [ ] Item title (not a Service Account Auth Token item)
- [ ] One JSON export path per origin from Get cookies.txt LOCALLY (gitignored)
- [ ] Section id + label per JSON file
- [ ] Origin URL map (cookie domain suffix → https://host/)
- [ ] Service account token env name (default OP_SERVICE_ACCOUNT_TOKEN)
- [ ] Protected item titles to refuse
```

Then:

1. Export cookies with Get cookies.txt LOCALLY as JSON. Gitignore those filenames.
2. Push with [scripts/sync-cookies.sh](scripts/sync-cookies.sh) (copy into the project or run from this skill directory).
3. Copy [scripts/fetch-session.js](scripts/fetch-session.js) into the app; set `OP_VAULT_ID` / `OP_ITEM_ID` from `op item get --format json` (`id` fields). Prefer env over hardcoding.
4. Implement inject using the mapping in [references/REFERENCE.md](references/REFERENCE.md). Prove login with URL / title / “has login form” — not by printing cookies.

## Export cookies

Use the Chrome extension **[Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)** ([source](https://github.com/kairi003/Get-cookies.txt-LOCALLY)). It reads cookies on-device and does not send them off the machine.

1. Log into the site in Chrome (and the SSO host, if the session spans two origins).
2. Open **Get cookies.txt LOCALLY** on that tab.
3. Set **Export Format** to **JSON** — not Netscape (`.txt`) and not Header String.
4. Click **Export** for the current site. Use **Export All Cookies** only when you must, then split the file by origin.
5. Save the `.json` next to the toolkit (gitignored). That file is the input to `scripts/sync-cookies.sh --json`.

Repeat on each origin you need a 1Password section for. Netscape `cookies.txt` is not a valid `--json` input.

## Push

Requires `op` and `python3`. Values go through a mode-`0600` temp template, then the template is deleted.

```bash
bash scripts/sync-cookies.sh \
  --vault YourVault \
  --title "example.com cookies" \
  --hostname "example.com, sso.example.com" \
  --url https://example.com \
  --json ./example.com.json --section app:example.com \
  --json ./sso.example.com.json --section sso:sso.example.com
```

`--section ID:LABEL` applies to the **previous** `--json`. If omitted, the section id is a slug of the filename stem and the label is the filename.

`--dry-run` previews. `--include-empty` stores blank values. `--keep-missing` leaves cookie fields that disappeared from the JSON.

If the title already exists, **update** that item. Do not create a second item with the same title.

## Fetch

Runtime apps use `@1password/sdk`, not `op`:

1. `createClient({ auth: process.env.OP_SERVICE_ACCOUNT_TOKEN, integrationName, integrationVersion })`
2. `client.items.get(vaultId, itemId)`
3. Collect fields by `sectionId` (include a legacy `cookies` section if present)
4. `JSON.parse(field.value)` when it looks like a cookie object; else `{ name: field.title, value: raw }`
5. Build `cookieHeader` only in memory. Return counts in logs.

Builtin fields to read when present: `hostname`, `credential` (access token), `username`.

## Inject

For each origin group: `goto(origin)` → `setCookie(...)`. If the batch fails, set cookies one-by-one and skip failures.

SSO cookies first when the site redirects through SSO, then the app origin, then any leftover origins. After cookies land, `goto` the app origin and inject `credential` into `localStorage` / `sessionStorage` as `access_token` when the app expects it.

## Safety

- Chat and logs: names, counts, hostname, booleans. Never values.
- Redact keys matching `cookie|access_token|authorization|password|credential|secret|set-cookie|cookieheader|bearer`.
- Service-account items are write-protected. Cookie sync and secret-push scripts must refuse those titles.
- Cookie JSON on disk is a live session. Keep it gitignored; treat the vault as source of truth after sync.
