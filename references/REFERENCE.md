# 1Password session cookies — reference

Supplement to [SKILL.md](../SKILL.md). Cookie-object shape, item schema, CLI
template rules, SDK fetch, and browser injection.

## Cookie JSON export

Export with **[Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)**. Set **Export Format** to **JSON** and save the download. The file is `JSON.stringify` of Chrome’s `chrome.cookies.Cookie[]` — an **array**:

```json
[
  {
    "name": "session",
    "value": "<secret>",
    "domain": ".example.com",
    "path": "/",
    "secure": true,
    "httpOnly": true,
    "sameSite": "lax",
    "hostOnly": false,
    "expirationDate": 1822245821
  }
]
```

`expirationDate` is Unix seconds. Chrome `sameSite` is often `lax`, `strict`,
`no_restriction`, or `unspecified`. `hostOnly: true` means the domain has no
leading dot.

Netscape `.txt` and Header String exports from the same extension are **not**
inputs to `sync-cookies.sh`. One JSON file per origin is easier to section in
1Password. Do not commit these files.

A fake export lives at [examples/example.com.cookies.json](../examples/example.com.cookies.json).

## 1Password item

| Property | Value |
|----------|--------|
| Category | `API_CREDENTIAL` |
| Title | Site session name, e.g. `example.com cookies` |
| Sections | One per origin (`id` slug, `label` hostname) |
| Cookie fields | `type: CONCEALED`, value = `JSON.stringify(cookie)` |
| Field id | `{sectionId}_{cookieName}` , suffix domain on collision, then `_2` |

Builtin fields (non-cookie):

| id | type | purpose |
|----|------|---------|
| `username` | STRING | SSO email if found in `userinfo*` cookies, else a placeholder |
| `credential` | CONCEALED | `access_token` extracted from `userinfo*` JSON cookie values, if any |
| `type` | MENU | `other` |
| `filename` | STRING | Source JSON filenames |
| `hostname` | STRING | Hosts this session covers |
| `notesPlain` | STRING / NOTES | Sync timestamp and cookie counts only |

Optional `urls[0]`: `{ "label": "website", "primary": true, "href": "https://example.com" }`.

Legacy section: some older items used section id `cookies` / label `Cookies` with
plain string values. Fetchers must still read that section.

### Field id rules

1. Slug the cookie name to `[A-Za-z0-9_]`. If it does not start with a letter, prefix `c_`.
2. Prefix with the section id: `sso_session`.
3. If that id is already used, append a slugged domain.
4. If still colliding, append `_2`, `_3`, …
5. Cap length at 80.

Cookie **labels** are the cookie name. Duplicates become `name @ domain`.

## CLI template (push)

Never pass cookie values as CLI flags. Write a JSON template mode `0600`:

```bash
op item create --vault VAULT --template /tmp/item.json --format json --url https://example.com
op item edit ITEM_ID --vault VAULT --template /tmp/item.json --format json
```

On update:

1. `op item get TITLE --vault VAULT --format json`
2. Refuse if `title` starts with `Service Account Auth Token:`
3. Keep non-cookie, non-builtin fields
4. Replace cookie-section fields with the new set (unless `--keep-missing`)
5. Refresh builtin fields and cookie sections
6. Delete the temp template in `finally`

Canonical script: [scripts/sync-cookies.sh](../scripts/sync-cookies.sh).

Look up ids after the first sync (do not guess):

```bash
op item get "example.com cookies" --vault YourVault --format json
# use .id and .vault.id  — print those ids only, never field values
```

## SDK fetch

```js
import { createClient } from "@1password/sdk";

const client = await createClient({
  auth: process.env.OP_SERVICE_ACCOUNT_TOKEN,
  integrationName: "My Agent",
  integrationVersion: "v0.1.0",
});
const item = await client.items.get(vaultId, itemId);
```

Parse:

```js
function parseCookieField(field) {
  const raw = field.value || "";
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && parsed.name) return parsed;
  } catch {
    /* older sync stored a bare cookie value */
  }
  return { name: field.title || "unknown", value: raw };
}
```

Filter `item.fields` by `sectionId`. Concatenate every cookie section plus
legacy `cookies`. Read `hostname` and `credential` by field `id`.

Log `{ hostname, cookieCount, cookiesWithValues, accessTokenPresent }` only.

Template: [scripts/fetch-session.js](../scripts/fetch-session.js).

The service account must have **read** on that vault. Creating the service
account is a human step in the 1Password app; do not invent tokens.

## Browser injection

`puppeteer-core` against installed Chrome is the default. Playwright uses the
same mapping (`context.addCookies` still needs a URL/domain that matches).

### Domain

```js
function chromeDomain(cookie, fallbackDomain) {
  const domain = (cookie.domain || "").trim();
  if (!domain) return fallbackDomain.startsWith(".") ? fallbackDomain : `.${fallbackDomain}`;
  if (cookie.hostOnly) return domain.replace(/^\./, "");
  return domain.startsWith(".") ? domain : `.${domain}`;
}
```

### sameSite + secure

| Export | Chrome `sameSite` |
|--------|-------------------|
| `strict` | `Strict` |
| `none` or `no_restriction` | `None` |
| anything else | `Lax` |

If `sameSite === "None"` and `secure` is false, force `sameSite` to `Lax`.
Chrome rejects `SameSite=None` without `Secure`.

Set `expires` from `expirationDate` when it is a number (Unix seconds).

### Origin grouping

Map cookie host → origin URL:

1. Strip leading `.` from `chromeDomain(cookie)`.
2. Match the longest configured suffix (e.g. `sso.example.com` vs `example.com`).
3. Default to the primary app origin.

```js
await page.goto(origin, { waitUntil: "domcontentloaded", timeout: 60_000 });
try {
  await page.setCookie(...converted);
} catch {
  for (const cookie of converted) {
    try { await page.setCookie(cookie); } catch { /* skip expired/invalid */ }
  }
}
```

Navigate SSO origin first when present, then the app origin.

### Access token

If the item `credential` field is set and the site keeps auth in web storage:

```js
await page.evaluate((value) => {
  window.localStorage.setItem("access_token", value);
  window.sessionStorage.setItem("access_token", value);
}, token);
```

Adapt the key if the target app uses a different name. Do not log `value`.

### Login probe

Prove the session without secrets:

- URL does not look like `/login`, `/signin`, `/auth`, `/sso`
- No `input[type=password]`
- An app-specific logged-in marker (nav text, dashboard cards, etc.)

Empty cookie values from 1Password → fail fast: “Sync the JSON exports first.”

## Refresh loop (agents / watchers)

When login looks expired:

1. If fresh cookie JSON exists on disk, run `sync-cookies.sh`.
2. Fetch the item again via SDK.
3. Re-inject and re-probe once.
4. If still expired, tell the human to log in with Chrome, re-export JSON with Get cookies.txt LOCALLY, and re-run sync. Do not scrape passwords into 1Password.

A cooldown (for example 10 minutes) avoids hammering `op` on every tick.

## Redaction

```js
const SENSITIVE_KEY =
  /cookie|access[_-]?token|authorization|password|credential|secret|set-cookie|cookieheader|bearer/i;
```

Replace matching object keys with `[redacted]` or `[redacted len=N]`. Apply
before writing session JSON, chat messages, or console logs.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `OP_SERVICE_ACCOUNT_TOKEN is not set` | Export the token from the vault’s service-account item into `.env`. Do not read cookie JSON for this. |
| SDK `items.get` 404 | Wrong `OP_VAULT_ID` / `OP_ITEM_ID`. Re-read ids from `op item get --format json`. |
| Sync refuses to modify item | Title is a service-account token item. Use a different `--title`. |
| `no cookies to store` | Export files are missing or values are empty. Re-export while logged in with Get cookies.txt LOCALLY as JSON, or pass `--include-empty` only if you mean it. |
| JSON parse / not an array | The file is Netscape `.txt` or Header String. Re-export with **Export Format: JSON**. |
| Chrome `setCookie` throws | Expired cookie, `SameSite=None` without Secure, or domain mismatch. Skip that cookie; check `hostOnly`. |
| Logged in on one host, bounced on SSO | Inject SSO origin cookies first; confirm the SSO JSON file was included in sync. |
| Cookie JSON in git | Delete it, commit the removal, keep the filename in `.gitignore`. Vault is the source of truth. |
| `op` not signed in | `op signin` / unlock the 1Password app. Agents cannot complete biometric unlock for the user. |

## Two-origin SSO example

A typical split is app cookies on `example.com` and SSO cookies on a second
host. Keep that as two JSON exports, two item sections, and inject SSO first.

When porting, keep the split (toolkit push vs app fetch). Do not copy vault
ids, item ids, or cookie files into a new repo.
