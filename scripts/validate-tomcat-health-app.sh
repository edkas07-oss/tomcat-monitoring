#!/usr/bin/env bash
#
# Purpose: Validate Tomcat health fixture static contracts without running containers.
# Usage: ./scripts/validate-tomcat-health-app.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly APP_ROOT="${PROJECT_ROOT}/fixtures/tomcat-health-app"
readonly WEB_XML="${APP_ROOT}/WEB-INF/web.xml"
readonly HEALTH_JSP="${APP_ROOT}/WEB-INF/health.jsp"

fail() {
    printf 'TOMCAT HEALTH APP VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_text() {
    local expected_text="$1"
    local target_file="$2"

    grep --fixed-strings --quiet "${expected_text}" "${target_file}" \
        || fail "Contract mismatch in ${target_file#"${PROJECT_ROOT}/"}: ${expected_text}"
}

validate_contract() {
    [[ -f "${WEB_XML}" ]] || fail "WEB-INF/web.xml not found."
    [[ -f "${HEALTH_JSP}" ]] || fail "WEB-INF/health.jsp not found."

    require_text '<jsp-file>/WEB-INF/health.jsp</jsp-file>' "${WEB_XML}"
    require_text '<url-pattern>/health</url-pattern>' "${WEB_XML}"
    require_text 'contentType="application/json; charset=UTF-8"' "${HEALTH_JSP}"
    require_text '{"status":"UP"}' "${HEALTH_JSP}"
}

main() {
    validate_contract
    printf 'Tomcat health app source validation passed: lab fixture static contract is valid.\n'
}

main "$@"
