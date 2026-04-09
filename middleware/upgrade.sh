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

FORCE_REBUILD=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE_REBUILD=true ;;
        -h|--help)
            echo "Usage: ./upgrade.sh [--force]"
            echo "  --force   Rebuild all containers even if no changes detected"
            exit 0 ;;
    esac
done

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
    if [ "$FORCE_REBUILD" = true ]; then
        warn "Already up to date — rebuilding all (--force)."
    else
        ok "Already up to date — nothing to do. Use --force to rebuild anyway."
        exit 0
    fi
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

# ── Fix file permissions ───────────────────────────
# servers.json must be writable by the benem-admin container (runs as appuser)
[ -f servers.json ] && chmod 666 servers.json

# ── Validate Caddyfile ─────────────────────────────

echo ""
echo -e "${CYAN}── Validating Caddyfile ──────────────────────────${NC}"
docker run --rm \
  --env-file .env \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.9-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
  || die "Caddyfile is invalid — aborting upgrade."
ok "Caddyfile valid."

# ── Detect changed services ────────────────────────

echo ""
echo -e "${CYAN}── Detecting changes ─────────────────────────────${NC}"

# Compare current HEAD against the commit before pull
CHANGED_FILES=$(git diff --name-only "$LOCAL" "$REMOTE" 2>/dev/null || echo "")
BUILD_SERVICES=""
RECREATE_ONLY=""

if [ -z "$CHANGED_FILES" ] && [ "$FORCE_REBUILD" = true ]; then
    warn "No file changes detected — rebuilding all (--force)."
    BUILD_SERVICES="bhnm-apns benem-admin benem-pwa"
elif [ -z "$CHANGED_FILES" ]; then
    ok "No file changes detected — skipping rebuild."
else
    # bhnm-apns: middleware files that affect the app image (exclude admin subdir, config-only files)
    if echo "$CHANGED_FILES" | grep -E '^middleware/' | grep -vE '^middleware/(benem-admin/|Caddyfile$|docker-compose\.yml$|upgrade\.sh$|setup\.sh$|\.env)' | grep -q .; then
        BUILD_SERVICES="$BUILD_SERVICES bhnm-apns"
        info "bhnm-apns: changes detected"
    fi

    # benem-admin: middleware/benem-admin/ files
    if echo "$CHANGED_FILES" | grep -q '^middleware/benem-admin/'; then
        BUILD_SERVICES="$BUILD_SERVICES benem-admin"
        info "benem-admin: changes detected"
    fi

    # benem-pwa: pwa/ files
    if echo "$CHANGED_FILES" | grep -q '^pwa/'; then
        BUILD_SERVICES="$BUILD_SERVICES benem-pwa"
        info "benem-pwa: changes detected"
    fi

    # caddy: never rebuilt (image-based), but recreate if Caddyfile or .env changed
    if echo "$CHANGED_FILES" | grep -qE '^middleware/(Caddyfile|\.env)'; then
        RECREATE_ONLY="$RECREATE_ONLY caddy"
        info "caddy: config changed, will recreate"
    fi

    if [ -z "$BUILD_SERVICES" ] && [ -z "$RECREATE_ONLY" ]; then
        ok "Changes don't affect any service — skipping rebuild."
    fi
fi

# Trim leading whitespace
BUILD_SERVICES=$(echo "$BUILD_SERVICES" | xargs)
RECREATE_ONLY=$(echo "$RECREATE_ONLY" | xargs)

# ── Rebuild changed images ────────────────────────

if [ -n "$BUILD_SERVICES" ]; then
    echo ""
    echo -e "${CYAN}── Rebuilding: ${BUILD_SERVICES} ───────────────────${NC}"
    docker compose build --no-cache $BUILD_SERVICES 2>&1 | grep -v -e "^#" -e "^$" || die "docker compose build failed."
    ok "Images built: $BUILD_SERVICES"
else
    info "No images to rebuild."
fi

# ── Restart services ──────────────────────────────

echo ""
echo -e "${CYAN}── Restarting services ───────────────────────────${NC}"

if [ -n "$BUILD_SERVICES" ]; then
    docker compose up -d --force-recreate $BUILD_SERVICES
    ok "Restarted: $BUILD_SERVICES"
fi

if [ -n "$RECREATE_ONLY" ]; then
    docker compose up -d --force-recreate $RECREATE_ONLY
    ok "Recreated: $RECREATE_ONLY"
fi

# If nothing specific was targeted, ensure everything is up
if [ -z "$BUILD_SERVICES" ] && [ -z "$RECREATE_ONLY" ]; then
    docker compose up -d
    ok "All services up."
fi

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
