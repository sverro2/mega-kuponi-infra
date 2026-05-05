# FTL Route Validation Script

This script validates that all routes return HTTP 200 status codes across multiple locales/domains using the `force-domain` cookie mechanism.

## Overview

The validation script:
- Tests multiple URLs across different domain locales
- Uses HEAD requests for efficient testing
- Forces specific locales using the `force-domain` cookie mechanism
- Replaces URL placeholders with actual IDs from configuration
- Shows only errors for clean output
- Provides a summary of all checks
- Includes 150ms delay between checks to be server-friendly

### How the force-domain Cookie Works

The `force-domain` cookie is used to test locale-specific behavior without changing the actual URL domain. When testing:

1. **Base URL**: The script transforms URLs to match the target domain (e.g., `www.megakuponi.hr` → `www.megacupones.cl`)
2. **Cookie Header**: A `force-domain` cookie is set with the value of the domain being tested
3. **Server Behavior**: The server uses this cookie to serve content as if the request came from that specific locale
4. **Result**: This allows comprehensive testing of all locales from a single execution point

Example request:
```bash
curl --head \
  --cookie "force-domain=https://www.megacupones.cl" \
  "https://www.megacupones.cl/tiendas"
```

## Prerequisites

- `bash` shell
- `curl` command
- `jq` JSON processor

### Installing jq

**Ubuntu/Debian:**
```bash
sudo apt-get install jq
```

**macOS:**
```bash
brew install jq
```

**Other systems:**
Visit https://stedolan.github.io/jq/download/

## Configuration Files

### `config/urls-to-check.json`
Contains the list of URL patterns to validate. Supports placeholders like:
- `<coupon-with-code-id>` - Coupon with a code
- `<coupon-with-sale-id>` - Coupon with a sale
- `<shop-id>` - Shop identifier
- `<category-id>` - Category identifier
- `<blog-article-id>` - Blog article identifier
- `<author-id>` - Author identifier

Example:
```json
[
  "https://www.megakuponi.hr/",
  "https://www.megakuponi.hr/trgovine/<shop-id>",
  "https://www.megakuponi.hr/kategorije/<category-id>"
]
```

### `config/domains-to-check.json`
Contains the list of domains to test against. Each URL will be tested with each domain as the `force-domain` cookie value.

Example:
```json
[
  "https://www.megakuponi.hr",
  "https://www.megakuponi.rs",
  "https://www.megacupones.cl"
]
```

### `config/placeholders.json`
Maps domain-specific placeholder values. This allows different domains to use different sample IDs for testing.

Example:
```json
{
  "https://www.megakuponi.hr": {
    "coupon-with-code-id": "actual-code-coupon-id",
    "shop-id": "amazon",
    "category-id": "fashion",
    "blog-article-id": "sample-article",
    "author-id": "1"
  }
}
```

## Usage

### Basic Usage

Run the script from the validation directory:

```bash
cd scripts/bash/ftl-validation
./run.sh
```

Or from anywhere in the project:

```bash
./scripts/bash/ftl-validation/run.sh
```

### Quick Test

Before running the full validation (which tests all domains and URLs), you can run a quick test to verify the setup:

```bash
cd scripts/bash/ftl-validation
./test-quick.sh
```

The quick test only checks:
- 2 domains (first and last from config)
- 3 simple URLs (homepage, shops page, blog)
- Takes ~10 seconds instead of minutes

This is useful for:
- Verifying the script setup is correct
- Quick smoke testing after configuration changes
- Debugging issues before full validation

### Output

The script provides:
1. **Real-time error reporting** - Only failed checks are shown
2. **Domain success confirmations** - Green checkmark when all URLs pass for a domain
3. **Final summary** - Total checks, failures, success rate, and duration

#### Success Output Example:
```
==================================================
  FTL Route Validation
==================================================

Testing 20 URLs across 14 domains...

✓ All checks passed for www.megakuponi.hr
✓ All checks passed for www.megakuponi.rs
✓ All checks passed for www.megacupones.cl

==================================================
  Summary
==================================================
Total checks: 280
Failed checks: 0
Success rate: 100.00%
Duration: 45s

✓ All routes validated successfully!
```

#### Failure Output Example:
```
✗ ERROR [www.megakuponi.ba] https://www.megakuponi.ba/trgovine/invalid-shop - Status: 404
✗ ERROR [www.megacupones.cl] https://www.megacupones.cl/categorias/missing - Status: 500
```

## How It Works

1. **Load Configuration**: Reads URLs, domains, and placeholders from JSON files
2. **Domain Iteration**: For each domain in `domains-to-check.json`:
   - **URL Iteration**: For each URL in `urls-to-check.json`:
     - Replace the base domain in the URL to match the current test domain
     - Replace placeholders (e.g., `<shop-id>`) with actual values from `placeholders.json`
     - Send HEAD request with `force-domain` cookie set to the current domain
     - Check if response is 200 OK
     - Report errors immediately (non-200 responses)
3. **Summary**: Display overall statistics (total checks, failures, success rate, duration)

### Example Flow

For URL `https://www.megakuponi.hr/trgovine/<shop-id>` and domain `https://www.megacupones.cl`:

1. Transform URL: `https://www.megacupones.cl/trgovine/<shop-id>`
2. Replace placeholder: `https://www.megacupones.cl/trgovine/amazon`
3. Request: `curl --head --cookie "force-domain=https://www.megacupones.cl" "https://www.megacupones.cl/trgovine/amazon"`
4. Verify: Status code = 200

### Fetching Real Sample IDs

To automatically fetch real IDs from your live sites for the placeholders:

```bash
cd scripts/bash/ftl-validation
./fetch-sample-ids.sh
```

This script will:
- Visit each domain in `domains-to-check.json`
- Scrape sample IDs for shops, categories, blog posts, etc.
- Update `placeholders.json` with the discovered values
- Backup the existing `placeholders.json` before updating

**Note**: This process may take several minutes depending on the number of domains and network speed.

## Customization

### Adding New URLs

Edit `config/urls-to-check.json`:
```json
[
  "https://www.megakuponi.hr/new-route",
  "https://www.megakuponi.hr/new-route/<placeholder-id>"
]
```

### Adding New Domains

Edit `config/domains-to-check.json`:
```json
[
  "https://www.new-domain.com"
]
```

### Updating Placeholder Values

Edit `config/placeholders.json` to add domain-specific test data:
```json
{
  "https://www.new-domain.com": {
    "shop-id": "actual-shop-slug",
    "category-id": "actual-category-slug"
  }
}
```

## Exit Codes

- `0` - All checks passed
- `1` - One or more checks failed or configuration error

## Troubleshooting

### "jq is not installed"
Install jq using your package manager (see Prerequisites section).

### "URLs file not found"
Ensure you're running the script from the correct directory or that the config files exist.

### Timeouts
The script uses:
- `--max-time 10` - Maximum 10 seconds per request
- `--connect-timeout 5` - 5 seconds to establish connection

Adjust these in the script if needed for slower connections.

### Invalid Placeholder IDs
If routes with placeholders are failing, verify:
1. The placeholder values in `placeholders.json` are valid
2. The resources (shops, categories, etc.) exist on the target domain

## Performance

- Uses HEAD requests (faster than GET)
- 150ms delay between each check to be server-friendly
- Parallel execution not implemented to avoid overwhelming servers
- Expected duration: ~2-3 seconds per URL per domain + 150ms delay
- For 20 URLs × 14 domains = ~60-90 seconds total (including delays)

## Future Enhancements

Potential improvements:
- Parallel execution with concurrency limits
- Automatic placeholder discovery
- Response time tracking
- HTML validation for non-200 responses
- CI/CD integration
- Configurable timeout values
- Retry logic for transient failures