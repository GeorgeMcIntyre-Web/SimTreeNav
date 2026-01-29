#!/bin/bash
#
# Secret Scanner for SimTreeNav
# Scans for hardcoded secrets with severity-based reporting
#
# Usage: bash scripts/security/scan-secrets.sh
# Exit code: 0 = no secrets, 1 = secrets found

set -euo pipefail

echo "=== SimTreeNav Secret Scanner ==="
echo ""

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Counters
HIGH_RISK_FINDINGS=0
MEDIUM_RISK_FINDINGS=0
LOW_RISK_FINDINGS=0

# Secret patterns (extended)
PATTERNS=(
    "password\s*="
    "password\s*:"
    "token\s*="
    "token\s*:"
    "secret\s*="
    "secret\s*:"
    "apikey\s*="
    "api_key\s*="
    "access_key\s*="
    "PRIVATE_KEY"
    "BEGIN RSA PRIVATE KEY"
    "BEGIN OPENSSH PRIVATE KEY"
    "github_pat_[a-zA-Z0-9]{36,}"
    "ghp_[a-zA-Z0-9]{36,}"
    "AKIA[0-9A-Z]{16}"  # AWS Access Key ID
    "sk_live_[0-9a-zA-Z]{24,}"  # Stripe Secret Key
)

# Join patterns with |
PATTERN_STRING=$(IFS="|"; echo "${PATTERNS[*]}")

echo "📋 Scan Configuration:"
echo "   Patterns: ${#PATTERNS[@]} secret patterns"
echo "   High-risk files: .env, .ini, .conf, .yaml, .xml, .psd1"
echo "   Medium-risk files: .json (credentials/secrets/config names)"
echo "   Low-risk files: All others (with exclusions)"
echo ""

# ============================================================================
# HIGH RISK SCAN: Files that should NEVER contain secrets
# ============================================================================
echo "🔴 HIGH RISK: Scanning files that should never contain secrets..."

HIGH_RISK_FILES=$(find . -type f \( \
    -name "*.env" -o \
    -name ".env.*" -o \
    -name "*.ini" -o \
    -name "*.conf" -o \
    -name "*.config" -o \
    -name "*.yaml" -o \
    -name "*.yml" -o \
    -name "*.xml" -o \
    -name "*.psd1" \
    \) \
    -not -path "./.git/*" \
    -not -path "./node_modules/*" \
    -not -path "./out/*" \
    -not -path "./.vscode/*" \
    -not -path "./.claude/*" \
    -not -path "./.github/workflows/*" \
    2>/dev/null || true)

if [ -n "$HIGH_RISK_FILES" ]; then
    while IFS= read -r file; do
        MATCHES=$(grep -niE "$PATTERN_STRING" "$file" 2>/dev/null || true)
        if [ -n "$MATCHES" ]; then
            echo -e "${RED}❌ HIGH RISK: $file${NC}"
            echo "$MATCHES" | head -5  # Show first 5 matches
            if [ $(echo "$MATCHES" | wc -l) -gt 5 ]; then
                echo "   ... and $(( $(echo "$MATCHES" | wc -l) - 5 )) more matches"
            fi
            echo ""
            ((HIGH_RISK_FINDINGS++))
        fi
    done <<< "$HIGH_RISK_FILES"
fi

if [ $HIGH_RISK_FINDINGS -eq 0 ]; then
    echo -e "${GREEN}✓ No secrets in high-risk files${NC}"
else
    echo -e "${RED}⚠️  Found secrets in $HIGH_RISK_FINDINGS high-risk file(s)${NC}"
fi
echo ""

# ============================================================================
# MEDIUM RISK SCAN: JSON files with suspicious names
# ============================================================================
echo "🟡 MEDIUM RISK: Scanning JSON files with credential-like names..."

MEDIUM_RISK_JSON=$(find . -type f \( \
    -name "*credential*.json" -o \
    -name "*secret*.json" -o \
    -name "*password*.json" -o \
    -name "*token*.json" -o \
    -name "*auth*.json" -o \
    -name "*key*.json" -o \
    -name "appsettings*.json" -o \
    -name "config*.json" \
    \) \
    -not -path "./.git/*" \
    -not -path "./node_modules/*" \
    -not -path "./out/*" \
    -not -path "./.vscode/*" \
    -not -path "./.claude/*" \
    -not -path "./test/fixtures/*" \
    2>/dev/null || true)

if [ -n "$MEDIUM_RISK_JSON" ]; then
    while IFS= read -r file; do
        # Look for non-placeholder values
        MATCHES=$(grep -niE "$PATTERN_STRING" "$file" 2>/dev/null | grep -vE "(CHANGEME|YOUR_.*_HERE|<.*>|null|\"\"|\[\])" || true)
        if [ -n "$MATCHES" ]; then
            echo -e "${YELLOW}⚠️  MEDIUM RISK: $file${NC}"
            echo "$MATCHES" | head -3
            if [ $(echo "$MATCHES" | wc -l) -gt 3 ]; then
                echo "   ... and $(( $(echo "$MATCHES" | wc -l) - 3 )) more matches"
            fi
            echo ""
            ((MEDIUM_RISK_FINDINGS++))
        fi
    done <<< "$MEDIUM_RISK_JSON"
fi

if [ $MEDIUM_RISK_FINDINGS -eq 0 ]; then
    echo -e "${GREEN}✓ No secrets in medium-risk JSON files${NC}"
else
    echo -e "${YELLOW}⚠️  Found secrets in $MEDIUM_RISK_FINDINGS medium-risk JSON file(s)${NC}"
fi
echo ""

# ============================================================================
# LOW RISK SCAN: Everything else with safe exclusions
# ============================================================================
echo "ℹ️  LOW RISK: Scanning remaining files (with exclusions)..."

LOW_RISK_MATCHES=$(grep -rniE "$PATTERN_STRING" . \
    --exclude-dir={.git,node_modules,.vscode,.claude,out} \
    --exclude="*.md" \
    --exclude="*.log" \
    --exclude="*.ps1" \
    --exclude="*.psm1" \
    --exclude="*.sql" \
    --exclude="*.env" \
    --exclude="*.ini" \
    --exclude="*.conf" \
    --exclude="*.config" \
    --exclude="*.yaml" \
    --exclude="*.yml" \
    --exclude="*.xml" \
    --exclude="*.psd1" \
    --exclude="*.json" \
    --exclude=".secretsignore" \
    --exclude="scan-secrets.sh" \
    2>/dev/null || true)

if [ -n "$LOW_RISK_MATCHES" ]; then
    echo "$LOW_RISK_MATCHES" | head -10
    if [ $(echo "$LOW_RISK_MATCHES" | wc -l) -gt 10 ]; then
        echo "   ... and $(( $(echo "$LOW_RISK_MATCHES" | wc -l) - 10 )) more matches"
    fi
    LOW_RISK_FINDINGS=$(echo "$LOW_RISK_MATCHES" | wc -l)
    echo ""
    echo -e "${YELLOW}⚠️  Found $LOW_RISK_FINDINGS potential secret(s) in low-risk files${NC}"
    echo "   (These may be false positives - review manually)"
else
    echo -e "${GREEN}✓ No secrets in low-risk files${NC}"
fi
echo ""

# ============================================================================
# SUMMARY AND EXIT
# ============================================================================
echo "=== Scan Summary ==="
echo -e "${RED}High-risk findings:   $HIGH_RISK_FINDINGS${NC}"
echo -e "${YELLOW}Medium-risk findings: $MEDIUM_RISK_FINDINGS${NC}"
echo "Low-risk findings:    $LOW_RISK_FINDINGS"
echo ""

TOTAL_FINDINGS=$((HIGH_RISK_FINDINGS + MEDIUM_RISK_FINDINGS + LOW_RISK_FINDINGS))

if [ $HIGH_RISK_FINDINGS -gt 0 ]; then
    echo -e "${RED}❌ FAILED: Secrets detected in high-risk files${NC}"
    echo ""
    echo "📖 Remediation steps:"
    echo "   1. Remove hardcoded secrets immediately"
    echo "   2. Add files to .gitignore"
    echo "   3. Rotate compromised credentials"
    echo "   4. Use environment variables or credential managers"
    echo ""
    exit 1
elif [ $MEDIUM_RISK_FINDINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Secrets detected in medium-risk files${NC}"
    echo ""
    echo "📖 Review these files:"
    echo "   - Are these template files? Add placeholders (CHANGEME, <YOUR_KEY_HERE>)"
    echo "   - Are these test fixtures? Move to test/fixtures/ and document"
    echo "   - Are these real secrets? Remove and rotate immediately"
    echo ""
    echo "To fail the build, these must be resolved or moved to low-risk category"
    exit 1
elif [ $LOW_RISK_FINDINGS -gt 0 ]; then
    echo -e "${GREEN}✓ PASSED with low-risk findings${NC}"
    echo ""
    echo "Low-risk findings are informational only and do not block CI."
    echo "Review manually during code review."
    exit 0
else
    echo -e "${GREEN}✅ PASSED: No secrets detected${NC}"
    exit 0
fi
