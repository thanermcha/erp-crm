#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hosts_file="${GROWERP_HOSTS_FILE:-/etc/hosts}"
local_ip="${GROWERP_LOCAL_IP:-127.0.0.1}"
cert_source="${script_dir}/certs/growerp.local.crt"
cert_target_dir="${GROWERP_CA_CERT_DIR:-/usr/local/share/ca-certificates}"
cert_target="${cert_target_dir}/growerp-local.crt"
dry_run=0

hosts=(
    "backend.growerp.local"
    "admin.growerp.local"
    "support.growerp.local"
    "health.growerp.local"
)

if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=1
elif [[ "${1:-}" != "" ]]; then
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
fi

run_root() {
    if [[ "${dry_run}" == "1" ]]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
        return
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return
    fi

    sudo "$@"
}

update_hosts() {
    local tmp_hosts
    local changed=0
    local host

    tmp_hosts="$(mktemp)"
    cp "${hosts_file}" "${tmp_hosts}"

    for host in "${hosts[@]}"; do
        if ! grep -Eq "(^|[[:space:]])${host}([[:space:]]|$)" "${tmp_hosts}"; then
            printf '%s %s\n' "${local_ip}" "${host}" >> "${tmp_hosts}"
            changed=1
        fi
    done

    if [[ "${changed}" == "1" ]]; then
        run_root cp "${tmp_hosts}" "${hosts_file}"
        if [[ "${dry_run}" == "1" ]]; then
            echo "Hosts would be updated in ${hosts_file}"
        else
            echo "Hosts updated in ${hosts_file}"
        fi
    else
        echo "Hosts already present in ${hosts_file}"
    fi

    rm -f "${tmp_hosts}"
}

install_certificate() {
    if [[ ! -f "${cert_source}" ]]; then
        echo "Missing certificate: ${cert_source}" >&2
        exit 1
    fi

    run_root mkdir -p "${cert_target_dir}"
    run_root cp "${cert_source}" "${cert_target}"

    if command -v update-ca-certificates >/dev/null 2>&1; then
        run_root update-ca-certificates
        if [[ "${dry_run}" == "1" ]]; then
            echo "System certificate store would be updated."
        else
            echo "System certificate store updated."
        fi
    else
        echo "Installed ${cert_target}, but update-ca-certificates is not available."
        echo "Import the certificate manually in your OS/browser trust store."
    fi
}

print_status() {
    local host

    if [[ "${dry_run}" == "1" ]]; then
        echo
        echo "Dry run complete. No system files were changed."
        return
    fi

    echo
    echo "Current host resolution:"
    for host in "${hosts[@]}"; do
        printf ' - %s: ' "${host}"
        getent hosts "${host}" || echo "not resolved"
    done

    echo
    echo "Browser probe:"
    if curl -sS -o /dev/null -w ' - backend status=%{http_code} err=%{errormsg}\n' \
        "https://backend.growerp.local:8443/status"; then
        true
    else
        echo " - Browser probe failed. If the stack is up, clear the browser cache/service worker next."
    fi
}

update_hosts
install_certificate
print_status
