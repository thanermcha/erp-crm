#!/usr/bin/env bash
# Configure Google SMTP for GrowERP (ainexus@blahsoftware.ia.br)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose-override.yaml"

echo "Gere um App Password em: https://myaccount.google.com/apppasswords"
echo "App name: GrowERP CRM"
read -rsp "App Password (16 caracteres): " SMTP_PASS
echo
SMTP_PASS_CLEAN="${SMTP_PASS// /}"

cat >> "$COMPOSE_FILE" << EOF

  # SMTP config (Google Workspace)
  moqui-server:
    environment:
      - SMTP_USER=ainexus@blahsoftware.ia.br
      - SMTP_PASSWORD=${SMTP_PASS_CLEAN}
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=587
      - SMTP_STARTTLS=true
      - default_locale=pt_BR
      - default_time_zone=America/Belem
EOF

echo "Reinicie: docker compose -f docker-compose.yaml -f docker-compose-override.yaml restart moqui-server"
echo "Teste: envie um email template via REST API."
