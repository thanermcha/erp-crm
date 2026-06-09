#!/usr/bin/env bash

set -euo pipefail

base_url="${GROWERP_BASE_URL:-https://backend.growerp.local:8443}"
support_user="${GROWERP_SUPPORT_USER:-SystemSupport}"
support_password="${GROWERP_SUPPORT_PASSWORD:-moqui}"
local_ip="${GROWERP_LOCAL_IP:-127.0.0.1}"
client_port="${GROWERP_CLIENT_PORT:-8443}"
curl_args=(-fsS)
browser_warnings=()

# The local development certificate is self-signed. GROWERP_CURL_RESOLVE keeps
# verification independent from /etc/hosts while still sending the correct host.
if [[ "${GROWERP_INSECURE_TLS:-1}" == "1" ]]; then
    curl_args+=(-k)
fi
if [[ -n "${GROWERP_CURL_RESOLVE:-backend.growerp.local:8443:127.0.0.1}" ]]; then
    curl_args+=(--resolve "${GROWERP_CURL_RESOLVE:-backend.growerp.local:8443:127.0.0.1}")
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

warn_browser() {
    browser_warnings+=("$1")
}

check_browser_prerequisites() {
    local browser_base_url="https://backend.growerp.local:${client_port}"
    local missing_hosts=()
    local host

    if ! command -v getent >/dev/null 2>&1; then
        warn_browser "Skipping host-resolution checks because 'getent' is not available."
    else
        for host in backend.growerp.local admin.growerp.local support.growerp.local health.growerp.local; do
            if ! getent hosts "${host}" >/dev/null 2>&1; then
                missing_hosts+=("${host}")
            fi
        done

        if [[ "${#missing_hosts[@]}" -gt 0 ]]; then
            warn_browser \
                "Missing host resolution for: ${missing_hosts[*]}. Run 'bash ./docker/fix-local-browser-env.sh' or add them to /etc/hosts/local DNS before testing in a browser."
        fi
    fi

    if [[ "${#missing_hosts[@]}" -eq 0 ]]; then
        if ! curl -fsS --connect-timeout 5 --max-time 15 \
            "${browser_base_url}/status" >/dev/null 2>&1; then
            warn_browser \
                "HTTPS trust check failed for ${browser_base_url}. Run 'bash ./docker/fix-local-browser-env.sh' or trust docker/certs/growerp.local.crt in the OS/browser certificate store."
        fi
    fi

    if [[ "${#browser_warnings[@]}" -eq 0 ]]; then
        echo "Browser prerequisites OK: host resolution and HTTPS trust look ready."
        return
    fi

    echo "Browser prerequisites pending:"
    printf ' - %s\n' "${browser_warnings[@]}"
    echo "Repository validation still passed because curl uses --resolve and -k for the local self-signed certificate."

    if [[ "${GROWERP_ENFORCE_BROWSER_PREREQS:-0}" == "1" ]]; then
        exit 1
    fi
}

login() {
    local username="$1"
    local password="$2"
    local classification="$3"
    local response

    response="$(curl "${curl_args[@]}" -X POST \
        --data-urlencode "username=${username}" \
        --data-urlencode "password=${password}" \
        --data-urlencode "classificationId=${classification}" \
        "${base_url}/rest/s1/growerp/100/Login")"

    if [[ "$(jq -r '.authenticate.apiKey // empty' <<<"${response}")" == "" ]]; then
        echo "Login failed for ${username} (${classification})" >&2
        jq . <<<"${response}" >&2
        exit 1
    fi

    echo "Login OK: ${username} (${classification})"
}

check_client() {
    local app="$1"
    local classification="$2"
    local host="${app}.growerp.local"
    local client_url="https://${host}:${client_port}"
    local config

    curl "${curl_args[@]}" --resolve "${host}:${client_port}:${local_ip}" \
        "${client_url}/" >/dev/null
    config="$(curl "${curl_args[@]}" --resolve "${host}:${client_port}:${local_ip}" \
        "${client_url}/assets/assets/cfg/app_settings.json")"

    if [[ "$(jq -r '.classificationId // empty' <<<"${config}")" != "${classification}" ]] ||
        [[ "$(jq -r '.databaseUrl // empty' <<<"${config}")" != "${base_url}" ]]; then
        echo "Invalid client configuration: ${app}" >&2
        jq . <<<"${config}" >&2
        exit 1
    fi

    echo "Client OK: ${app} (${classification})"
}

require_command curl
require_command jq

curl "${curl_args[@]}" "${base_url}/status" >/dev/null
echo "Backend health OK: ${base_url}/status"

if [[ "${GROWERP_CHECK_CLIENTS:-1}" == "1" ]]; then
    check_client "admin" "AppAdmin"
    check_client "support" "AppSupport"
    check_client "health" "AppHealth"
fi

login "${support_user}" "${support_password}" "AppSupport"

if [[ -n "${GROWERP_ADMIN_USER:-}" && -n "${GROWERP_ADMIN_PASSWORD:-}" ]]; then
    login "${GROWERP_ADMIN_USER}" "${GROWERP_ADMIN_PASSWORD}" "AppAdmin"
else
    echo "Admin login skipped: set GROWERP_ADMIN_USER and GROWERP_ADMIN_PASSWORD to validate it."
fi

check_browser_prerequisites
