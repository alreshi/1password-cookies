#!/usr/bin/env bash
# Push cookie JSON exports into one 1Password API_CREDENTIAL item.
# Each cookie is a concealed field; the value is the full cookie object JSON.
# Secrets go through a temp template (mode 0600), never as process arguments.
set -euo pipefail

VAULT="${OP_VAULT:-}"
TITLE="${OP_ITEM_TITLE:-}"
HOSTNAME_FIELD="${OP_HOSTNAME:-}"
ITEM_URL="${OP_ITEM_URL:-}"
DRY_RUN=0
INCLUDE_EMPTY=0
KEEP_MISSING=0
ACCOUNT=""
USERNAME_FALLBACK=""
JSON_PATHS=()
SECTION_IDS=()
SECTION_LABELS=()
PROTECTED_TITLES=()

usage() {
  cat <<'EOF'
Push cookie JSON files into one 1Password item (create or update).

Usage:
  sync-cookies.sh --vault VAULT --title TITLE [options]

Options:
  --json PATH              Cookie JSON array (repeatable)
  --section ID[:LABEL]     Section for the previous --json (id, optional label)
  --vault NAME             Destination vault (or $OP_VAULT)
  --title TITLE            Item title (or $OP_ITEM_TITLE)
  --hostname HOSTS         Value for the hostname field
  --url URL                Website URL on the item
  --username NAME          Fallback username if SSO email is not found
  --account ACCOUNT        1Password account shorthand/ID
  --protected-title TITLE  Extra title this script must refuse (repeatable)
  --include-empty          Also store cookies whose value is empty
  --keep-missing           Do not delete cookie fields absent from the JSON
  --dry-run                Preview without saving
  -h, --help               Show this help

Always refuses titles that start with "Service Account Auth Token:".
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

assign_section() {
  local idx=$((${#JSON_PATHS[@]} - 1))
  [[ $idx -ge 0 ]] || die "--section must follow --json"
  local spec="${1:-}"
  [[ -n "$spec" ]] || die "--section requires ID[:LABEL]"
  SECTION_IDS[$idx]="${spec%%:*}"
  if [[ "$spec" == *:* ]]; then
    SECTION_LABELS[$idx]="${spec#*:}"
  else
    SECTION_LABELS[$idx]="${spec}"
  fi
  [[ -n "${SECTION_IDS[$idx]}" ]] || die "--section id is empty"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_PATHS+=("${2:-}")
      SECTION_IDS+=("")
      SECTION_LABELS+=("")
      shift 2
      ;;
    --section)
      assign_section "${2:-}"
      shift 2
      ;;
    --vault)
      VAULT="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME_FIELD="${2:-}"
      shift 2
      ;;
    --url)
      ITEM_URL="${2:-}"
      shift 2
      ;;
    --username)
      USERNAME_FALLBACK="${2:-}"
      shift 2
      ;;
    --account)
      ACCOUNT="${2:-}"
      shift 2
      ;;
    --protected-title)
      PROTECTED_TITLES+=("${2:-}")
      shift 2
      ;;
    --include-empty)
      INCLUDE_EMPTY=1
      shift
      ;;
    --keep-missing)
      KEEP_MISSING=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

need_cmd op
need_cmd python3

[[ ${#JSON_PATHS[@]} -gt 0 ]] || die "pass at least one --json PATH"
[[ -n "$VAULT" ]] || die "--vault (or \$OP_VAULT) is required"
[[ -n "$TITLE" ]] || die "--title (or \$OP_ITEM_TITLE) is required"

if [[ "$TITLE" == "Service Account Auth Token:"* ]]; then
  die "refusing to modify: $TITLE"
fi

for json_path in "${JSON_PATHS[@]}"; do
  [[ -n "$json_path" ]] || die "--json requires a path"
  [[ -f "$json_path" ]] || die "JSON file not found: $json_path"
done

op_cmd() {
  if [[ -n "$ACCOUNT" ]]; then
    op --account "$ACCOUNT" "$@"
  else
    op "$@"
  fi
}

op_cmd vault get "$VAULT" >/dev/null || die "vault not found or CLI not signed in: $VAULT"

json_array() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
}

PATHS_JSON="$(json_array "${JSON_PATHS[@]}")"
SECTION_IDS_JSON="$(json_array "${SECTION_IDS[@]}")"
SECTION_LABELS_JSON="$(json_array "${SECTION_LABELS[@]}")"
PROTECTED_TITLES_TEXT="$(printf '%s\n' "${PROTECTED_TITLES[@]+"${PROTECTED_TITLES[@]}"}")"

export VAULT TITLE DRY_RUN INCLUDE_EMPTY KEEP_MISSING ACCOUNT
export HOSTNAME_FIELD ITEM_URL USERNAME_FALLBACK
export PATHS_JSON SECTION_IDS_JSON SECTION_LABELS_JSON PROTECTED_TITLES_TEXT

python3 - <<'PY'
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

vault = os.environ["VAULT"]
title = os.environ["TITLE"]
dry_run = os.environ["DRY_RUN"] == "1"
include_empty = os.environ["INCLUDE_EMPTY"] == "1"
keep_missing = os.environ["KEEP_MISSING"] == "1"
account = os.environ.get("ACCOUNT", "")
hostname_field = os.environ.get("HOSTNAME_FIELD", "")
item_url = os.environ.get("ITEM_URL", "")
username_fallback = os.environ.get("USERNAME_FALLBACK", "")
protected_titles = {
    line for line in os.environ.get("PROTECTED_TITLES_TEXT", "").splitlines() if line
}
paths = json.loads(os.environ["PATHS_JSON"])
section_ids = json.loads(os.environ["SECTION_IDS_JSON"])
section_labels = json.loads(os.environ["SECTION_LABELS_JSON"])
specs = []
for path, sid, slabel in zip(paths, section_ids, section_labels):
    name = Path(path).name
    stem = Path(path).stem
    if not sid:
        sid = re.sub(r"[^A-Za-z0-9_]", "_", stem)[:32] or "cookies"
    if not slabel:
        slabel = name
    specs.append({"path": path, "section_id": sid, "section_label": slabel})

KNOWN_COOKIE_SECTION_IDS = {"cookies"}
KNOWN_COOKIE_SECTION_LABELS = {"Cookies"}
for spec in specs:
    KNOWN_COOKIE_SECTION_IDS.add(spec["section_id"])
    KNOWN_COOKIE_SECTION_LABELS.add(spec["section_label"])

BUILTIN_IDS = {
    "username",
    "credential",
    "type",
    "filename",
    "hostname",
    "notesPlain",
}


def op_base():
    cmd = ["op"]
    if account:
        cmd.extend(["--account", account])
    return cmd


def run_op(args, allow_fail=False):
    completed = subprocess.run(
        op_base() + args,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        if allow_fail:
            return None
        err = (completed.stderr or completed.stdout or "op command failed").strip()
        sys.stderr.write(f"error: {err}\n")
        sys.exit(completed.returncode)
    return completed.stdout


def website_url(domain):
    host = (domain or "").lstrip(".")
    return f"https://{host}" if host else ""


def field_id(prefix, name, domain, seen):
    base = re.sub(r"[^A-Za-z0-9_]", "_", name)
    if not base or not re.match(r"[A-Za-z]", base):
        base = f"c_{base}"
    extra = re.sub(r"[^A-Za-z0-9_]", "_", (domain or "").lstrip("."))
    candidate = f"{prefix}_{base}"[:80]
    if extra and candidate in seen:
        candidate = f"{prefix}_{base}_{extra}"[:80]
    n = 2
    original = candidate
    while candidate in seen:
        candidate = f"{original}_{n}"[:80]
        n += 1
    seen.add(candidate)
    return candidate


def is_cookie_field(field):
    section = field.get("section") or {}
    return (
        section.get("id") in KNOWN_COOKIE_SECTION_IDS
        or section.get("label") in KNOWN_COOKIE_SECTION_LABELS
    )


def cookie_label(name, domain, used_labels):
    label = name
    if label in used_labels:
        label = f"{name} @ {domain}" if domain else f"{name} @ duplicate"
    used_labels.add(label)
    return label


def extract_sso_identity(cookies):
    email = ""
    access_token = ""
    for cookie in cookies:
        name = cookie.get("name") or ""
        if not name.startswith("userinfo"):
            continue
        raw = cookie.get("value") or ""
        try:
            info = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(info, dict):
            continue
        if not email and isinstance(info.get("email"), str):
            email = info["email"]
        if not access_token and isinstance(info.get("access_token"), str):
            access_token = info["access_token"]
    return email, access_token


def cookie_fields_for(cookie_list, section_id, section_label, seen_ids):
    fields = []
    skipped = []
    used_labels = set()
    for cookie in cookie_list:
        name = cookie.get("name")
        if not name:
            continue
        value = cookie.get("value")
        if value is None:
            value = ""
        if not isinstance(value, str):
            value = str(value)
        if not include_empty and value == "":
            skipped.append(name)
            continue
        domain = cookie.get("domain") or ""
        payload = dict(cookie)
        payload["value"] = value
        fields.append(
            {
                "id": field_id(section_id, name, domain, seen_ids),
                "section": {"id": section_id, "label": section_label},
                "type": "CONCEALED",
                "label": cookie_label(name, domain, used_labels),
                "value": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            }
        )
    return fields, skipped


def write_template(payload):
    handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        suffix=".json",
        prefix="op-cookies-",
        delete=False,
    )
    try:
        os.fchmod(handle.fileno(), stat.S_IRUSR | stat.S_IWUSR)
        json.dump(payload, handle, ensure_ascii=False)
        handle.flush()
        return handle.name
    finally:
        handle.close()


def is_protected(item_title):
    if not item_title:
        return False
    if item_title.startswith("Service Account Auth Token:"):
        return True
    return item_title in protected_titles


sources = []
all_cookies = []
seen_ids = set()
new_cookie_fields = []
skipped = []
section_defs = []
file_summaries = []

for spec in specs:
    json_path = spec["path"]
    with open(json_path, encoding="utf-8") as fh:
        cookies = json.load(fh)
    if not isinstance(cookies, list):
        sys.stderr.write(f"error: {json_path} must be an array of cookie objects\n")
        sys.exit(1)
    fields, skipped_here = cookie_fields_for(
        cookies, spec["section_id"], spec["section_label"], seen_ids
    )
    sources.append({**spec, "cookies": cookies, "fields": fields})
    all_cookies.extend(cookies)
    new_cookie_fields.extend(fields)
    skipped.extend(skipped_here)
    section_defs.append({"id": spec["section_id"], "label": spec["section_label"]})
    file_summaries.append(f"{Path(json_path).name}:{len(fields)}/{len(cookies)}")

if not new_cookie_fields:
    sys.stderr.write(
        "error: no cookies to store. Export JSON files with values, "
        "or pass --include-empty.\n"
    )
    sys.exit(1)

domains = [c.get("domain") for c in all_cookies if c.get("domain")]
primary_domain = domains[0] if domains else ""
url = item_url or website_url(hostname_field.split(",")[0].strip() if hostname_field else primary_domain)
sso_email, access_token = extract_sso_identity(all_cookies)
hostname_value = hostname_field or ", ".join(
    dict.fromkeys(d.lstrip(".") for d in domains if d)
)

notes = (
    f"Session cookies. "
    f"Last pushed {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}. "
    f"{len(new_cookie_fields)} concealed cookie fields. "
    + " ".join(file_summaries)
)

builtin_fields = [
    {
        "id": "username",
        "type": "STRING",
        "label": "username",
        "value": sso_email or username_fallback or (hostname_value.split(",")[0].strip() if hostname_value else "session"),
    },
    {
        "id": "credential",
        "type": "CONCEALED",
        "label": "credential",
        "value": access_token,
    },
    {"id": "type", "type": "MENU", "label": "type", "value": "other"},
    {
        "id": "filename",
        "type": "STRING",
        "label": "filename",
        "value": ", ".join(Path(spec["path"]).name for spec in specs),
    },
    {
        "id": "hostname",
        "type": "STRING",
        "label": "hostname",
        "value": hostname_value,
    },
    {
        "id": "notesPlain",
        "type": "STRING",
        "purpose": "NOTES",
        "label": "notesPlain",
        "value": notes,
    },
]

existing_raw = run_op(
    ["item", "get", title, "--vault", vault, "--format", "json"],
    allow_fail=True,
)
existing = json.loads(existing_raw) if existing_raw else None

if existing and is_protected(existing.get("title") or ""):
    sys.stderr.write(f"error: refusing to modify: {existing.get('title')}\n")
    sys.exit(1)
if is_protected(title):
    sys.stderr.write(f"error: refusing to modify: {title}\n")
    sys.exit(1)

if existing:
    payload = dict(existing)
    payload["title"] = title
    payload["category"] = "API_CREDENTIAL"
    sections = [
        s
        for s in (payload.get("sections") or [])
        if s.get("id") not in KNOWN_COOKIE_SECTION_IDS
        and s.get("label") not in KNOWN_COOKIE_SECTION_LABELS
    ]
    sections.extend(section_defs)
    payload["sections"] = sections

    kept = []
    existing_cookie_by_key = {}
    for field in payload.get("fields") or []:
        if is_cookie_field(field):
            section = (field.get("section") or {}).get("id") or ""
            existing_cookie_by_key[(section, field.get("label"))] = field
            continue
        if field.get("id") in BUILTIN_IDS:
            continue
        kept.append(field)

    if keep_missing:
        incoming = {
            ((f.get("section") or {}).get("id"), f.get("label"))
            for f in new_cookie_fields
        }
        leftover = [
            field
            for key, field in existing_cookie_by_key.items()
            if key not in incoming
        ]
        cookie_out = leftover + new_cookie_fields
    else:
        cookie_out = new_cookie_fields

    payload["fields"] = builtin_fields + kept + cookie_out
    if url:
        payload["urls"] = [{"label": "website", "primary": True, "href": url}]
    item_ref = existing.get("id") or title
    args = ["item", "edit", item_ref, "--vault", vault, "--format", "json"]
    action = "would update" if dry_run else "updated"
else:
    payload = {
        "title": title,
        "category": "API_CREDENTIAL",
        "sections": section_defs,
        "fields": builtin_fields + new_cookie_fields,
    }
    if url:
        payload["urls"] = [{"label": "website", "primary": True, "href": url}]
    args = ["item", "create", "--vault", vault, "--format", "json"]
    action = "would create" if dry_run else "created"

if dry_run:
    args.append("--dry-run")
if url:
    args.extend(["--url", url])

template_path = write_template(payload)
try:
    args.extend(["--template", template_path])
    result = json.loads(run_op(args) or "{}")
finally:
    try:
        os.unlink(template_path)
    except OSError:
        pass

print(
    f"{action:14} {result.get('title') or title}  id={result.get('id') or (existing or {}).get('id') or '(dry-run)'}",
    flush=True,
)
print(f"vault          {vault}", flush=True)
for source in sources:
    print(
        f"section        {source['section_label']}  {len(source['fields'])} cookies  ({Path(source['path']).name})",
        flush=True,
    )
if skipped:
    print(
        f"skipped        {len(skipped)} empty  (use --include-empty to store them)",
        flush=True,
    )
print(
    f"access_token   {'stored' if access_token else 'not found in userinfo cookies'}",
    flush=True,
)
print(f"item           op://{vault}/{title}", flush=True)
PY
