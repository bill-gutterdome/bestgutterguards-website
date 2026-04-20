#!/bin/bash
# BestGutterGuards.net Deployment Script
# Usage: ./scripts/deploy.sh [--prod]

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/src"
ASSETS_DIR="$PROJECT_DIR/assets"
DEPLOY_DIR=$(mktemp -d)
ENV="${1:-preview}"

echo "=== BestGutterGuards.net Deployment ==="
echo "Source: $SRC_DIR"
echo "Environment: $ENV"

# Pre-deployment checks
echo ""
echo "[1/5] Pre-deployment checks..."

# Check required files exist
REQUIRED_FILES=("index.html" "sitemap.xml" "robots.txt")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SRC_DIR/$file" ]; then
        echo "ERROR: Required file missing: $file"
        exit 1
    fi
done
echo "  ✓ All required files present"

# Check for image references that might be broken
echo ""
echo "[2/5] Checking image references..."
MISSING_IMAGES=()
for img in $(grep -oE 'src="[^"]+\.(png|jpg|jpeg|gif|svg)"' "$SRC_DIR/index.html" | sed 's/src="//;s/"$//' | sort -u); do
    if [ ! -f "$SRC_DIR/$img" ] && [ ! -f "$ASSETS_DIR/$img" ]; then
        MISSING_IMAGES+=("$img")
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo "  ⚠ WARNING: Referenced images not found:"
    for img in "${MISSING_IMAGES[@]}"; do
        echo "    - $img"
    done
    read -p "Continue without these images? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 1
    fi
else
    echo "  ✓ All image references resolved"
fi

# Prepare deployment directory
echo ""
echo "[3/5] Preparing deployment..."
cp -r "$SRC_DIR"/* "$DEPLOY_DIR/"
if [ -d "$ASSETS_DIR" ] && [ "$(ls -A "$ASSETS_DIR")" ]; then
    cp -r "$ASSETS_DIR"/* "$DEPLOY_DIR/"
fi
echo "  ✓ Deployment directory ready"

# Show what will be deployed
echo ""
echo "[4/5] Files to deploy:"
ls -la "$DEPLOY_DIR"

# Get Vercel token from Infisical
export PATH="$HOME/.local/bin:$PATH"
VERCEL_TOKEN=$(infisical secrets get VERCEL_API --env=dev --path=/root 2>/dev/null | grep -o 'vcp_[a-zA-Z0-9]*' | head -1)

if [ -z "$VERCEL_TOKEN" ]; then
    echo "ERROR: Could not retrieve Vercel token from Infisical"
    exit 1
fi

# Deploy
echo ""
echo "[5/5] Deploying to Vercel..."
cd "$DEPLOY_DIR"

if [ "$ENV" == "--prod" ] || [ "$ENV" == "production" ]; then
    vercel deploy --prod --yes --token="$VERCEL_TOKEN"
    echo "  ✓ Production deployment complete"
else
    vercel deploy --yes --token="$VERCEL_TOKEN"
    echo "  ✓ Preview deployment complete"
fi

# Cleanup
rm -rf "$DEPLOY_DIR"

# Update status
echo ""
echo "Updating project status..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg date "$TIMESTAMP" '.lastUpdated = $date | .recentActivity += ["\($date): Deployed to '\$ENV'"]' \
    "$PROJECT_DIR/status.json" > "$PROJECT_DIR/status.json.tmp" && \
    mv "$PROJECT_DIR/status.json.tmp" "$PROJECT_DIR/status.json"

echo ""
echo "=== Deployment Complete ==="
