#!/usr/bin/env bash
# BHNM APNs Middleware — Upgrade Script
# Pulls latest code, rebuilds the image, and restarts the service.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${CYAN}  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

echo ""
echo "┌──────────────────────────────────────────────┐"
echo "│   BHNM APNs Middleware — Upgrade              │"
echo "└──────────────────────────────────────────────┘"
echo ""

# ── Preflight ──────────────────────────────────────

[ -f "docker-compose.yml" ] || die "Run this script from the bhnm-apns repo root."
[ -f ".env" ]               || die ".env not found — run ./setup.sh first."
command -v docker    >/dev/null || die "docker not found."
command -v git       >/dev/null || die "git not found."

BEFORE=$(cat VERSION 2>/dev/null || echo "unknown")
info "Current version : $BEFORE"

# ── Pull latest code ───────────────────────────────

echo ""
echo -e "${CYAN}── Pulling latest code ───────────────────────────${NC}"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "Branch: $BRANCH"

git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
    warn "Already up to date — rebuilding anyway."
else
    git pull --ff-only || die "git pull failed. Resolve conflicts manually and re-run."
    ok "Code updated."
fi

AFTER=$(cat VERSION 2>/dev/null || echo "unknown")
if [ "$BEFORE" != "$AFTER" ]; then
    info "Version: $BEFORE → $AFTER"
else
    info "Version unchanged: $AFTER"
fi

# ── Validate Caddyfile ─────────────────────────────

echo ""
echo -e "${CYAN}── Validating Caddyfile ──────────────────────────${NC}"
docker run --rm \
  --env-file .env \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.9-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
  || die "Caddyfile is invalid — aborting upgrade."
ok "Caddyfile valid."

# ── Rebuild image ──────────────────────────────────

echo ""
echo -e "${CYAN}── Rebuilding Docker image ───────────────────────${NC}"
docker compose build --no-cache 2>&1 | grep -v -e "^#" -e "^$" || die "docker compose build failed."
ok "Image built."

# ── Restart service ────────────────────────────────

echo ""
echo -e "${CYAN}── Restarting service ────────────────────────────${NC}"
docker compose up -d --force-recreate
ok "Service restarted."

# ── Health check ───────────────────────────────────

echo ""
echo -e "${CYAN}── Health check ──────────────────────────────────${NC}"

# Give the container a moment to start
sleep 3

# Health checks run inside the containers (ports are not exposed to the host — they're behind Caddy)
FAILED=0

HEALTH_APNS=$(docker compose exec -T bhnm-apns python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8889/health').read().decode())" 2>/dev/null || echo "")
if echo "$HEALTH_APNS" | grep -q '"status":"running"'; then
    ok "bhnm-apns is healthy: $HEALTH_APNS"
else
    warn "bhnm-apns health check failed — check logs:"
    docker compose logs bhnm-apns --tail 20
    FAILED=1
fi

HEALTH_ADMIN=$(docker compose exec -T benem-admin python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8001/admin/health').read().decode())" 2>/dev/null || echo "")
if echo "$HEALTH_ADMIN" | grep -q '"status":"running"'; then
    ok "benem-admin is healthy: $HEALTH_ADMIN"
else
    warn "benem-admin health check failed — check logs:"
    docker compose logs benem-admin --tail 20
    FAILED=1
fi

# Use 127.0.0.1 explicitly — `localhost` resolves to IPv6 ::1 first on alpine,
# but nginx inside benem-pwa only listens on IPv4 0.0.0.0:80, which gives a
# false "Connection refused" even when the container is healthy.
HEALTH_PWA=$(docker compose exec -T benem-pwa wget -q -O - http://127.0.0.1/ 2>/dev/null | head -c 50 || echo "")
if echo "$HEALTH_PWA" | grep -qi '<!doctype html'; then
    ok "benem-pwa is serving the SPA shell."
else
    warn "benem-pwa health check failed — check logs:"
    docker compose logs benem-pwa --tail 20
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo ""
    die "One or more health checks failed."
fi

# ── Done ───────────────────────────────────────────

echo ""
echo "┌──────────────────────────────────────────────┐"
echo "│   Upgrade complete ✓                          │"
echo "└──────────────────────────────────────────────┘"
echo ""
