#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# Load JSON files
URLS_FILE="$CONFIG_DIR/urls-to-check.json"
DOMAINS_FILE="$CONFIG_DIR/domains-to-check.json"
TEST_DOMAIN="https://www.megakuponi.hr"
VALID_IDS_CACHE=""

# Check if a parameter is provided and use it as TEST_DOMAIN
if [[ $# -gt 0 ]]; then
    TEST_DOMAIN="$1"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq to parse JSON files.${NC}"
    echo "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (Mac)"
    exit 1
fi

# Check if config files exist
if [[ ! -f "$URLS_FILE" ]]; then
    echo -e "${RED}Error: URLs file not found at $URLS_FILE${NC}"
    exit 1
fi

if [[ ! -f "$DOMAINS_FILE" ]]; then
    echo -e "${RED}Error: Domains file not found at $DOMAINS_FILE${NC}"
    exit 1
fi

# Fetch valid IDs from TEST_DOMAIN
echo "Fetching valid IDs from $TEST_DOMAIN/currently-valid-ids..."
VALID_IDS_CACHE=$(curl -s "$TEST_DOMAIN/currently-valid-ids")

if [[ -z "$VALID_IDS_CACHE" ]]; then
    echo -e "${YELLOW}Warning: Could not fetch valid IDs from $TEST_DOMAIN/currently-valid-ids${NC}"
    echo "Using default placeholder values..."
fi

# Load URLs and domains from JSON files
URLS=$(jq -r '.[]' "$URLS_FILE")
DOMAINS=$(jq -r '.[]' "$DOMAINS_FILE")

# Function to extract domain from URL
extract_domain() {
    echo "$1" | sed -E 's|https?://([^/]+).*|\1|'
}

# Function to get a sample ID for placeholders from a domain
get_sample_ids() {
    local domain=$1

    # Try to load from fetched valid IDs
    if [[ -n "$VALID_IDS_CACHE" ]]; then
        local placeholders=$(echo "$VALID_IDS_CACHE" | jq -r --arg domain "$domain" '.[] | select(.domain == $domain) | ."valid-ids" // {} | to_entries | map("\(.key)=\(.value)") | .[]' 2>/dev/null)

        if [[ -n "$placeholders" ]]; then
            echo "$placeholders"
            return
        fi
    fi

    # Fallback to default values if fetch failed or domain not found
    echo "coupon-with-code-id=test-code-coupon"
    echo "coupon-with-sale-id=test-sale-coupon"
    echo "shop-id=amazon"
    echo "category-id=fashion"
    echo "blog-article-id=sample-blog-post"
    echo "special-id=special-id"
    echo "author-id=1"
}

# Function to replace placeholders in URL with actual values
replace_placeholders() {
    local url=$1
    local domain=$2

    # Check if URL has placeholders
    if [[ ! "$url" =~ \<.*\> ]]; then
        echo "$url"
        return
    fi

    # Get sample IDs
    local ids=$(get_sample_ids "$domain")

    # Replace placeholders with actual values
    local result="$url"
    while IFS='=' read -r key value; do
        result="${result//<$key>/$value}"
    done <<< "$ids"

    echo "$result"
}

# Function to check a single URL
check_url() {
    local url=$1
    local force_domain=$2
    local cookie_domain=$(extract_domain "$force_domain")

    # The url is already just a path (e.g., "/trgovine")
    # Replace any placeholders
    local test_path=$(replace_placeholders "$url" "$force_domain")

    # Make HEAD request with force-domain cookie
    # Combine TEST_DOMAIN with the path
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        --head \
        --cookie "force-domain=$force_domain" \
        --max-time 10 \
        --connect-timeout 5 \
        "$TEST_DOMAIN$test_path" 2>&1)

    # Check if response is 200
    if [[ "$response" != "200" ]]; then
        echo -e "${RED}✗ ERROR${NC} [${YELLOW}$cookie_domain${NC}] $TEST_DOMAIN$test_path - Status: $response"
        return 1
    fi

    return 0
}


# Main execution
echo "=================================================="
echo "  FTL Route Validation"
echo "=================================================="
echo ""
echo "Testing $(echo "$URLS" | wc -l) URLs across $(echo "$DOMAINS" | wc -l) domains..."
echo ""

total_checks=0
failed_checks=0
start_time=$(date +%s)

# Iterate through each domain
while IFS= read -r domain; do
    domain_name=$(extract_domain "$domain")
    domain_failed=0
    domain_total=0

    # Iterate through each URL
    while IFS= read -r url; do
        total_checks=$((total_checks + 1))
        domain_total=$((domain_total + 1))

        if ! check_url "$url" "$domain"; then
            failed_checks=$((failed_checks + 1))
            domain_failed=$((domain_failed + 1))
        fi

        # Wait 150ms between checks to avoid overwhelming servers
        sleep 0.15
    done <<< "$URLS"

    # Print domain summary only if there were no errors (quiet success)
    if [[ $domain_failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All checks passed for ${YELLOW}$domain_name${NC}"
    fi

done <<< "$DOMAINS"

end_time=$(date +%s)
duration=$((end_time - start_time))

# Print summary
echo ""
echo "=================================================="
echo "  Summary"
echo "=================================================="
echo "Total checks: $total_checks"
echo "Failed checks: $failed_checks"
echo "Success rate: $(awk "BEGIN {printf \"%.2f\", (($total_checks - $failed_checks) / $total_checks) * 100}")%"
echo "Duration: ${duration}s"
echo ""

if [[ $failed_checks -eq 0 ]]; then
    echo -e "${GREEN}✓ All routes validated successfully!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some routes failed validation. Please check the errors above.${NC}"
    exit 1
fi
