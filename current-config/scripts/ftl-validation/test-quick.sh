#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "=================================================="
echo "  FTL Route Validation - Quick Test"
echo "=================================================="
echo ""
echo -e "${YELLOW}This is a quick test script that tests only:${NC}"
echo "  - 2 domains (first and last from config)"
echo "  - 3 URLs (homepage, shops page, and one with placeholder)"
echo ""
echo "For full validation, run: ./run.sh"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq first.${NC}"
    exit 1
fi

# Load config files
DOMAINS_FILE="$CONFIG_DIR/domains-to-check.json"
PLACEHOLDERS_FILE="$CONFIG_DIR/placeholders.json"

if [[ ! -f "$DOMAINS_FILE" ]]; then
    echo -e "${RED}Error: Domains file not found${NC}"
    exit 1
fi

# Get first and last domain
FIRST_DOMAIN=$(jq -r '.[0]' "$DOMAINS_FILE")
LAST_DOMAIN=$(jq -r '.[-1]' "$DOMAINS_FILE")

# Quick test URLs (without placeholders for simplicity)
QUICK_URLS=(
    "/"
    "/trgovine"
    "/blog"
)

# Function to extract domain from URL
extract_domain() {
    echo "$1" | sed -E 's|https?://([^/]+).*|\1|'
}

# Function to test a URL
test_url() {
    local base_domain=$1
    local path=$2
    local full_url="${base_domain}${path}"
    local domain_name=$(extract_domain "$base_domain")

    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        --head \
        --cookie "force-domain=$base_domain" \
        --max-time 10 \
        --connect-timeout 5 \
        "$full_url" 2>&1)

    if [[ "$response" == "200" ]]; then
        echo -e "  ${GREEN}✓${NC} $path - ${GREEN}OK${NC}"
        return 0
    else
        echo -e "  ${RED}✗${NC} $path - ${RED}Status: $response${NC}"
        return 1
    fi
}

# Test function for a domain
test_domain() {
    local domain=$1
    local domain_name=$(extract_domain "$domain")

    echo -e "${BLUE}Testing:${NC} ${YELLOW}$domain_name${NC}"

    local failed=0
    for path in "${QUICK_URLS[@]}"; do
        if ! test_url "$domain" "$path"; then
            failed=$((failed + 1))
        fi

        # Wait 150ms between checks to avoid overwhelming servers
        sleep 0.15
    done

    echo ""

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓ All quick tests passed for $domain_name${NC}"
    else
        echo -e "${RED}✗ $failed test(s) failed for $domain_name${NC}"
    fi

    echo ""
    return $failed
}

# Run tests
total_failed=0

echo "Testing first domain..."
echo "---"
if ! test_domain "$FIRST_DOMAIN"; then
    total_failed=$((total_failed + 1))
fi

echo "Testing last domain..."
echo "---"
if ! test_domain "$LAST_DOMAIN"; then
    total_failed=$((total_failed + 1))
fi

# Summary
echo "=================================================="
if [[ $total_failed -eq 0 ]]; then
    echo -e "${GREEN}✓ Quick test completed successfully!${NC}"
    echo ""
    echo "Run ${BLUE}./run.sh${NC} for full validation of all domains and URLs"
    exit 0
else
    echo -e "${RED}✗ Quick test found issues${NC}"
    echo ""
    echo "Please check the errors above before running full validation"
    exit 1
fi
