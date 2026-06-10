#!/usr/bin/env bash
# Setup Gmail API Domain-Wide Delegation
set -euo pipefail

CRED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/webhook-server/credentials"
echo "1. Google Cloud Console:"
echo "   - Criar projeto 'GrowERP CRM Integration'"
echo "   - Ativar Gmail API + Admin SDK API"
echo "   - IAM > Service Accounts > criar 'growerp-crm-ingest'"
echo "   - Gerar chave JSON -> $CRED_DIR/google-service-account.json"
echo
echo "2. Google Admin Console (admin.google.com):"
echo "   - Seguranca > Controles de API > Domain-wide Delegation"
echo "   - Client ID do Service Account + escopos:"
echo "     https://www.googleapis.com/auth/gmail.readonly"
echo "     https://www.googleapis.com/auth/admin.directory.user.readonly"
echo "   - Delegar para: ainexus@blahsoftware.ia.br"
echo
echo "3. Teste:"
echo "   docker exec webhook-server python /app/gmail_ingest.py"
echo "   docker exec webhook-server python /app/gmail_ingest.py --push"
