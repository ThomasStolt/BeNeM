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

# ── Rebuild image ──────────────────────────────────

echo ""
echo -e "${CYAN}── Rebuilding Docker image ───────────────────────${NC}"
docker compose build --no-cache 2>&1 | grep -v "^#" || die "docker compose build failed."
ok "Image built."

# ── Restart service ────────────────────────────────

echo ""
echo -e "${CYAN}── Restarting service ────────────────────────────${NC}"
docker compose up -d
ok "Service restarted."

# ── Health check ───────────────────────────────────

echo ""
echo -e "${CYAN}── Health check ──────────────────────────────────${NC}"

# Give the container a moment to start
sleep 3

PORT=$(docker compose port bhnm-apns 8889 2>/dev/null | cut -d: -f2 || echo "8889")
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/health" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    HEALTH=$(curl -s "http://localhost:${PORT}/health")
    ok "Service is healthy: $HEALTH"
else
    warn "Health check returned HTTP $HTTP_STATUS — check logs:"
    echo ""
    docker compose logs bhnm-apns --tail 20
    exit 1
fi

# ── Done ───────────────────────────────────────────

echo ""
echo "┌──────────────────────────────────────────────┐"
echo "│   Upgrade complete ✓                          │"
echo "└──────────────────────────────────────────────┘"
echo ""
