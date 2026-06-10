#!/usr/bin/env bash
# Setup Ubuntu client for Flatpak CRM Blah Software
SERVER_IP="${1:-192.168.15.100}"
FLATPAK_FILE="${FLATPAK_FILE:-growerp-crm.flatpak}"

echo "1. /etc/hosts..."
for host in backend.growerp.local admin.growerp.local; do
  grep -q "$host" /etc/hosts 2>/dev/null || echo "$SERVER_IP $host" | sudo tee -a /etc/hosts >/dev/null
done

echo "2. SSL Certificate..."
curl -sL "https://backend.growerp.local/certs/growerp.local.crt" -o /tmp/growerp-local.crt 2>/dev/null && \
  sudo cp /tmp/growerp-local.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates || \
  echo "  Certificado nao disponivel"

echo "3. Flatpak..."
command -v flatpak &>/dev/null || sudo apt-get install -y flatpak

if [[ -f "$FLATPAK_FILE" ]]; then
  flatpak install --user --assumeyes "$FLATPAK_FILE"
  echo "Instalado! Execute: flatpak run io.growerp.crm.blah"
else
  echo "Copie $FLATPAK_FILE para este diretorio."
fi

echo "Dashboard: https://backend.growerp.local/crm/"
