#!/usr/bin/env bash
# Operator/SRE CLI helper to ingest Declarative Rulepacks into Diagnostic Service
# Supports:
#   1. Single Rule JSON Object: {...}
#   2. Batch Array of Rules:    [{...}, {...}]
#   3. Custom URL & Token: DIAGNOSTIC_URL="https://host:8443" BEARER_TOKEN="your-token" ./scripts/ingest-rule.sh <file>
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly DIAGNOSTIC_URL="${DIAGNOSTIC_URL:-https://localhost:${DIAGNOSTIC_PORT:-8443}}"
readonly AUTH_TOKEN="${BEARER_TOKEN:-test-token-12345}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

fail() {
    printf "${RED}✘ ERROR:${NC} %s\n" "$1" >&2
    exit 1
}

pass() {
    printf "${GREEN}✔ SUCCESS:${NC} %s\n" "$1"
}

info() {
    printf "${BLUE}ℹ INFO:${NC} %s\n" "$1"
}

if [[ $# -lt 1 ]]; then
    printf "Usage: $0 <path-to-rulepack.json>\n" >&2
    printf "Example:     $0 ~/proactive-rules.json\n" >&2
    printf "             cat rule.json | $0 -\n" >&2
    printf "             DIAGNOSTIC_URL=\"https://192.168.1.50:8443\" BEARER_TOKEN=\"my-token\" $0 ~/proactive-rules.json\n" >&2
    exit 1
fi

PAYLOAD_INPUT="$1"
PAYLOAD_CONTENT=""

if [[ "${PAYLOAD_INPUT}" == "-" ]]; then
    PAYLOAD_CONTENT="$(cat)"
else
    [[ -f "${PAYLOAD_INPUT}" ]] || fail "File not found: ${PAYLOAD_INPUT}"
    PAYLOAD_CONTENT="$(cat "${PAYLOAD_INPUT}")"
fi

# Validate JSON format
if ! echo "${PAYLOAD_CONTENT}" | jq . >/dev/null 2>&1; then
    fail "File content is not valid JSON format."
fi

# Detect JSON type: Array (batch) vs Object (single)
IS_ARRAY=$(echo "${PAYLOAD_CONTENT}" | jq 'if type == "array" then true else false end')

if [[ "${IS_ARRAY}" == "true" ]]; then
    TOTAL_RULES=$(echo "${PAYLOAD_CONTENT}" | jq 'length')
    info "Batch Rulepack detected: Contains ${TOTAL_RULES} rules."
    
    CREATED_COUNT=0
    CONFLICT_COUNT=0
    FAILED_COUNT=0

    for ((i = 0; i < TOTAL_RULES; i++)); do
        SINGLE_RULE=$(echo "${PAYLOAD_CONTENT}" | jq -c ".[$i]")
        BRANCH=$(echo "${SINGLE_RULE}" | jq -r '.branch // "UNKNOWN"')
        NAME=$(echo "${SINGLE_RULE}" | jq -r '.ruleName // "UNKNOWN"')

        RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "${DIAGNOSTIC_URL}/api/v1/rules" \
            -H "Authorization: Bearer ${AUTH_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${SINGLE_RULE}" || true)
        STATUS_CODE=$(echo "${RESPONSE}" | tail -n1)
        BODY=$(echo "${RESPONSE}" | sed '$d')

        if [[ "${STATUS_CODE}" == "201" ]]; then
            pass "Rule ${BRANCH} (${NAME}) successfully ingested (201 Created)."
            CREATED_COUNT=$((CREATED_COUNT + 1))
        elif [[ "${STATUS_CODE}" == "409" ]]; then
            printf "${YELLOW}⚠ SKIP:${NC} Rule ${BRANCH} (${NAME}) is already registered (409 Conflict).\n"
            CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
        else
            printf "${RED}✘ FAILED:${NC} Rule ${BRANCH} (${NAME}) rejected (${STATUS_CODE}): %s\n" "${BODY}" >&2
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done

    printf "\n${CYAN}=== Batch Ingestion Summary ===${NC}\n"
    printf "Total Processed : %d\n" "${TOTAL_RULES}"
    printf "${GREEN}Success (New)   : %d${NC}\n" "${CREATED_COUNT}"
    printf "${YELLOW}Skipped (Exist) : %d${NC}\n" "${CONFLICT_COUNT}"
    printf "${RED}Failed/Rejected : %d${NC}\n" "${FAILED_COUNT}"

    if [[ ${FAILED_COUNT} -gt 0 ]]; then
        exit 1
    fi
else
    BRANCH=$(echo "${PAYLOAD_CONTENT}" | jq -r '.branch // "UNKNOWN"')
    NAME=$(echo "${PAYLOAD_CONTENT}" | jq -r '.ruleName // "UNKNOWN"')
    info "Sending Rulepack ${BRANCH} (${NAME}) to ${DIAGNOSTIC_URL}/api/v1/rules..."

    RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "${DIAGNOSTIC_URL}/api/v1/rules" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD_CONTENT}" || true)
    STATUS_CODE=$(echo "${RESPONSE}" | tail -n1)
    BODY=$(echo "${RESPONSE}" | sed '$d')

    if [[ "${STATUS_CODE}" == "201" ]]; then
        pass "Rulepack ${BRANCH} (${NAME}) successfully ingested and active immediately (201 Created)."
        printf "${GREEN}Stored Rule Details:${NC}\n"
        echo "${BODY}" | jq .
    elif [[ "${STATUS_CODE}" == "409" ]]; then
        printf "${YELLOW}⚠ CONFLICT (409): Rule branch or name '${BRANCH}' is already registered.${NC}\n"
        echo "${BODY}" | jq .
    else
        fail "Ingestion rejected by 5-Layer Guard (Status: ${STATUS_CODE}): ${BODY}"
    fi
fi
