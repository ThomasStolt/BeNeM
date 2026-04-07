#!/usr/bin/env bash
# check-env.sh — Validate the middleware .env file for completeness and correctness.
# Run from the middleware/ directory: ./check-env.sh [path-to-env]
set -euo pipefail

ENV_FILE="${1:-.env}"
ERRORS=0
WARNINGS=0

red()    { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$1"; }
dim()    { printf '\033[0;90m%s\033[0m\n' "$1"; }

err()  { red    "  ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn() { yellow "  WARN:  $1"; WARNINGS=$((WARNINGS + 1)); }
ok()   { green  "  OK:    $1"; }

# ── File checks ──────────────────────────────────────────────────────────────

echo ""
echo "Checking $ENV_FILE ..."
echo ""

if [[ ! -f "$ENV_FILE" ]]; then
  red "FATAL: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

# ── Read value for a key from the .env file ──────────────────────────────────

val() {
  local key="$1"
  local line
  line=$(grep -m1 "^${key}=" "$ENV_FILE" 2>/dev/null || true)
  if [[ -n "$line" ]]; then
    echo "${line#*=}"
  fi
}

# ── Spelling check: detect unknown keys ──────────────────────────────────────

echo "── Checking for unknown variables ──"

KNOWN_KEYS="APNS_KEY_ID APNS_TEAM_ID APNS_BUNDLE_ID APNS_PRIVATE_KEY_B64 \
VAPID_PRIVATE_KEY VAPID_PUBLIC_KEY VAPID_CONTACT_EMAIL \
DOMAIN PWA_DOMAIN \
BASIC_AUTH_USER BASIC_AUTH_HASH \
BENEM_SECRET_KEY SESSION_SECRET TOTP_SECRET \
MIDDLEWARE_URL MIDDLEWARE_PORT WEBHOOK_SECRET \
BHNM_TLS_VERIFY PROXY_TOKEN \
DB_PATH SERVERS_JSON_PATH LOG_PATH APNS_DB_PATH \
COMPOSE_PROJECT_NAME"

# Extract all keys from .env (skip comments and blank lines)
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  key="${line%%=*}"
  found=0
  for known in $KNOWN_KEYS; do
    if [[ "$key" == "$known" ]]; then found=1; break; fi
  done
  if [[ $found -eq 0 ]]; then
    warn "'$key' is not a recognized variable — possible typo?"
  fi
done < "$ENV_FILE"
echo ""

# ── Required variables ───────────────────────────────────────────────────────

echo "── APNs (required for iOS push) ──"

for var in APNS_KEY_ID APNS_TEAM_ID APNS_BUNDLE_ID APNS_PRIVATE_KEY_B64; do
  v="$(val "$var")"
  if [[ -z "$v" ]]; then
    err "$var is not set"
  else
    ok "$var is set"
  fi
done

# Validate APNS_KEY_ID format (10-char alphanumeric)
v="$(val APNS_KEY_ID)"
if [[ -n "$v" && ! "$v" =~ ^[A-Z0-9]{10}$ ]]; then
  warn "APNS_KEY_ID '$v' doesn't look like a 10-char Apple key ID"
fi

# Validate APNS_TEAM_ID format (10-char alphanumeric)
v="$(val APNS_TEAM_ID)"
if [[ -n "$v" && ! "$v" =~ ^[A-Z0-9]{10}$ ]]; then
  warn "APNS_TEAM_ID '$v' doesn't look like a 10-char Apple team ID"
fi

# Validate APNS_PRIVATE_KEY_B64 is valid base64
v="$(val APNS_PRIVATE_KEY_B64)"
if [[ -n "$v" ]]; then
  if ! echo "$v" | base64 -d &>/dev/null; then
    err "APNS_PRIVATE_KEY_B64 is not valid base64"
  fi
fi
echo ""

# ── BeNeM Admin Portal ──────────────────────────────────────────────────────

echo "── BeNeM Admin Portal ──"

v="$(val BENEM_SECRET_KEY)"
if [[ -z "$v" ]]; then
  err "BENEM_SECRET_KEY is not set (needed for QR code generation and PWA scanning)"
elif [[ ! "$v" =~ ^[0-9a-fA-F]{64}$ ]]; then
  err "BENEM_SECRET_KEY must be exactly 64 hex characters (32 bytes), got ${#v} chars"
else
  ok "BENEM_SECRET_KEY is set (64 hex chars)"
fi

v="$(val SESSION_SECRET)"
if [[ -z "$v" ]]; then
  warn "SESSION_SECRET not set — will fall back to BENEM_SECRET_KEY for session signing"
elif [[ ${#v} -lt 32 ]]; then
  warn "SESSION_SECRET is short (${#v} chars) — recommend at least 32 chars"
else
  ok "SESSION_SECRET is set"
fi

v="$(val TOTP_SECRET)"
if [[ -z "$v" ]]; then
  warn "TOTP_SECRET not set — admin login will always fail (no TOTP code can match)"
elif [[ ! "$v" =~ ^[A-Z2-7=]+$ ]]; then
  warn "TOTP_SECRET doesn't look like base32 — expected A-Z and 2-7 only"
else
  ok "TOTP_SECRET is set (base32)"
fi
echo ""

# ── Domain / TLS ─────────────────────────────────────────────────────────────

echo "── Domain & TLS ──"

v="$(val DOMAIN)"
if [[ -z "$v" ]]; then
  warn "DOMAIN not set — Caddy won't know which hostname to serve TLS for"
elif [[ "$v" == *"example.com"* ]]; then
  err "DOMAIN still contains 'example.com' — update to your real domain"
else
  ok "DOMAIN=$v"
fi

v="$(val PWA_DOMAIN)"
if [[ -z "$v" ]]; then
  warn "PWA_DOMAIN not set — PWA hosting via Caddy won't work"
elif [[ "$v" == *"example.com"* ]]; then
  err "PWA_DOMAIN still contains 'example.com' — update to your real domain"
else
  ok "PWA_DOMAIN=$v"
fi
# Caddy Basic Auth for /admin
echo ""
echo "── Caddy Basic Auth ──"

v="$(val BASIC_AUTH_USER)"
if [[ -z "$v" ]]; then
  warn "BASIC_AUTH_USER not set — /admin routes won't have HTTP Basic Auth"
else
  ok "BASIC_AUTH_USER=$v"
fi

v="$(val BASIC_AUTH_HASH)"
if [[ -z "$v" ]]; then
  if [[ -n "$(val BASIC_AUTH_USER)" ]]; then
    err "BASIC_AUTH_HASH is not set but BASIC_AUTH_USER is — auth will fail"
  fi
elif [[ ! "$v" =~ ^\$2[aby]?\$ ]]; then
  warn "BASIC_AUTH_HASH doesn't look like a bcrypt hash (expected \$2a\$... or \$2b\$...)"
else
  ok "BASIC_AUTH_HASH is set (bcrypt)"
fi
echo ""

# ── VAPID / Web Push ────────────────────────────────────────────────────────

echo "── Web Push (VAPID) ──"

vapid_priv="$(val VAPID_PRIVATE_KEY)"
vapid_pub="$(val VAPID_PUBLIC_KEY)"
vapid_email="$(val VAPID_CONTACT_EMAIL)"

if [[ -z "$vapid_priv" && -z "$vapid_pub" ]]; then
  dim "  VAPID keys not set — Web Push disabled (OK if not using PWA push)"
else
  if [[ -z "$vapid_priv" ]]; then err "VAPID_PRIVATE_KEY is empty but VAPID_PUBLIC_KEY is set"; fi
  if [[ -z "$vapid_pub" ]]; then err "VAPID_PUBLIC_KEY is empty but VAPID_PRIVATE_KEY is set"; fi
  if [[ -n "$vapid_priv" && -n "$vapid_pub" ]]; then ok "VAPID key pair is set"; fi
  if [[ -z "$vapid_email" ]]; then
    warn "VAPID_CONTACT_EMAIL not set — some push services require it"
  elif [[ ! "$vapid_email" =~ ^mailto: ]]; then
    warn "VAPID_CONTACT_EMAIL should start with 'mailto:' (got '$vapid_email')"
  else
    ok "VAPID_CONTACT_EMAIL=$vapid_email"
  fi
fi
echo ""

# ── Optional configuration ──────────────────────────────────────────────────

echo "── Optional configuration ──"

v="$(val MIDDLEWARE_URL)"
if [[ -z "$v" ]]; then
  dim "  MIDDLEWARE_URL not set — generated QR links won't include push middleware URL"
elif [[ ! "$v" =~ ^https?:// ]]; then
  err "MIDDLEWARE_URL must start with http:// or https:// (got '$v')"
else
  ok "MIDDLEWARE_URL=$v"
fi

v="$(val WEBHOOK_SECRET)"
if [[ -z "$v" ]]; then
  dim "  WEBHOOK_SECRET not set — generated links won't include a default push secret"
else
  ok "WEBHOOK_SECRET is set"
fi

v="$(val PROXY_TOKEN)"
if [[ -z "$v" ]]; then
  dim "  PROXY_TOKEN not set — BHNM API proxy requests won't be authenticated"
else
  ok "PROXY_TOKEN is set"
fi

v="$(val BHNM_TLS_VERIFY)"
if [[ -n "$v" && "$v" != "true" && "$v" != "false" ]]; then
  warn "BHNM_TLS_VERIFY should be 'true' or 'false' (got '$v')"
elif [[ "$v" == "false" ]]; then
  yellow "  NOTE: BHNM_TLS_VERIFY=false — TLS certificate checks are disabled"
fi

v="$(val MIDDLEWARE_PORT)"
if [[ -n "$v" && ! "$v" =~ ^[0-9]+$ ]]; then
  err "MIDDLEWARE_PORT must be a number (got '$v')"
elif [[ -n "$v" ]]; then
  ok "MIDDLEWARE_PORT=$v"
fi
echo ""

# ── Docker paths (optional, have sensible defaults) ─────────────────────────

echo "── Docker paths ──"

v="$(val DB_PATH)"
if [[ -n "$v" ]]; then ok "DB_PATH=$v"; else dim "  DB_PATH not set (default: /data/bhnm_apns.db)"; fi

v="$(val SERVERS_JSON_PATH)"
if [[ -n "$v" ]]; then ok "SERVERS_JSON_PATH=$v"; else dim "  SERVERS_JSON_PATH not set (default: /data/servers.json)"; fi

v="$(val LOG_PATH)"
if [[ -n "$v" ]]; then ok "LOG_PATH=$v"; else dim "  LOG_PATH not set (default: /app/log/admin.jsonl)"; fi

v="$(val APNS_DB_PATH)"
if [[ -n "$v" ]]; then ok "APNS_DB_PATH=$v"; else dim "  APNS_DB_PATH not set (default: /data/bhnm_apns.db)"; fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "════════════════════════════════════"
if [[ $ERRORS -gt 0 ]]; then
  red "  $ERRORS error(s), $WARNINGS warning(s)"
  echo ""
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  yellow "  0 errors, $WARNINGS warning(s)"
  echo ""
  exit 0
else
  green "  All checks passed"
  echo ""
  exit 0
fi
