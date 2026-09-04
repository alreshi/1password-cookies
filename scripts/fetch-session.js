#!/usr/bin/env node
// Fetch a 1Password cookie-session item via the JS SDK.
// Copy into the project (needs @1password/sdk). Prints counts only — never values.
const { createClient } = require("@1password/sdk");

const SECTION_IDS = (process.env.OP_SECTION_IDS || "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

function requireEnv(name) {
  const value = (process.env[name] || "").trim();
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}

function buildCookieHeader(cookies) {
  return cookies
    .filter((cookie) => cookie && cookie.name && cookie.value)
    .map((cookie) => `${cookie.name}=${cookie.value}`)
    .join("; ");
}

function parseCookieField(field) {
  const raw = field.value || "";
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && parsed.name) {
      return parsed;
    }
  } catch {
    // Older syncs stored a bare cookie value.
  }
  return {
    name: field.title || "unknown",
    value: raw,
  };
}

function cookiesFromSection(item, sectionId) {
  return (item.fields || [])
    .filter((field) => field.sectionId === sectionId)
    .map(parseCookieField);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

async function fetchCookieSession(options = {}) {
  const token = options.token || requireEnv("OP_SERVICE_ACCOUNT_TOKEN");
  const vaultId = options.vaultId || requireEnv("OP_VAULT_ID");
  const itemId = options.itemId || requireEnv("OP_ITEM_ID");

  const client = await createClient({
    auth: token,
    integrationName: options.integrationName || "1Password cookie session",
    integrationVersion: options.integrationVersion || "v1.0.0",
  });
  const item = await client.items.get(vaultId, itemId);

  const presentIds = unique(
    (item.fields || []).map((field) => field.sectionId),
  );
  const requested = options.sectionIds || SECTION_IDS;
  const sectionIds = unique(
    requested.length > 0 ? [...requested, "cookies"] : [...presentIds, "cookies"],
  );

  const bySection = {};
  const cookies = [];
  for (const sectionId of sectionIds) {
    const list = cookiesFromSection(item, sectionId);
    if (list.length === 0) continue;
    bySection[sectionId] = list;
    cookies.push(...list);
  }

  const hostname =
    (item.fields || []).find((field) => field.id === "hostname")?.value || "";
  const accessToken =
    (item.fields || []).find((field) => field.id === "credential")?.value || "";

  return {
    cookies,
    bySection,
    hostname,
    accessToken,
    cookieHeader: buildCookieHeader(cookies),
  };
}

function sessionSummary(session) {
  const sectionCounts = {};
  for (const [sectionId, list] of Object.entries(session.bySection || {})) {
    sectionCounts[sectionId] = (list || []).filter((cookie) => cookie.value).length;
  }
  return {
    hostname: session.hostname,
    cookieCount: session.cookies.filter((cookie) => cookie.value).length,
    sectionCounts,
    accessTokenPresent: Boolean(session.accessToken),
    cookieHeaderReady: Boolean(session.cookieHeader),
  };
}

async function main() {
  const session = await fetchCookieSession();
  console.log(JSON.stringify(sessionSummary(session), null, 2));
}

module.exports = {
  fetchCookieSession,
  sessionSummary,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}
