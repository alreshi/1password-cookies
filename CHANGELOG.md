# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-04

### Added

- Agent skill for syncing Chrome cookie JSON into a 1Password API Credential item.
- `scripts/sync-cookies.sh` — create or update one item via `op --template`.
- `scripts/fetch-session.js` — `@1password/sdk` fetch template (counts only in logs).
- Browser injection rules (origin grouping, sameSite/hostOnly/Secure mapping).
- MIT license, security policy, and contributor documents.

[1.0.0]: https://github.com/alreshi/1password-cookies/releases/tag/v1.0.0
