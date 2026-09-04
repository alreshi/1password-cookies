# Security policy

## What this project handles

This skill moves **session cookies** into 1Password and back into a browser. A leaked export, vault item, or service-account token is equivalent to a live login.

## Reporting a vulnerability

**Do not** open a public issue for a security problem.

Use GitHub **Security Advisories** on this repository (Security → Report a vulnerability), or email the maintainer listed on the GitHub profile.

Include:

- What an attacker could do
- Steps to reproduce **without** real cookie values
- Affected script or document path

You should receive an acknowledgement within 7 days.

## Please never send

- Live cookie JSON
- `OP_SERVICE_ACCOUNT_TOKEN` values
- `cookieHeader` strings
- Screenshots of 1Password items that show concealed field values

Redact those to names and counts.

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes |

## Hardening notes for users

- Keep cookie JSON gitignored; treat the vault as source of truth after sync.
- Scope the 1Password service account to **read** the session-cookie vault only.
- Rotate the site session (log out everywhere) if an export or token may have leaked.
