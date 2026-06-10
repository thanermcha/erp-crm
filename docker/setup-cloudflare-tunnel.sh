#!/usr/bin/env bash
# Setup Cloudflare Tunnel for GrowERP backend
# Usage: TUNNEL_NAME=growerp-backend bash setup-cloudflare-tunnel.sh
set -euo pipefail

TUNNEL_NAME="${TUNNEL_NAME:-growerp-backend}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-webhooks.blahsoftware.ia.br}"
LOCAL_SERVICE="${LOCAL_SERVICE:-http://localhost:80}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.cloudflared}"

if ! command -v cloudflared &>/dev/null; then
  echo "Instale cloudflared primeiro."
  exit 1
fi

echo "1. Autenticar: cloudflared tunnel login"
cloudflared tunnel login

echo "2. Criar tunnel: $TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME" 2>/dev/null || echo "  Tunnel ja existe"
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
echo "   ID: $TUNNEL_ID"

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json
ingress:
  - hostname: $TUNNEL_DOMAIN
    service: $LOCAL_SERVICE
  - service: http_status:404
EOF
echo "3. Config: $CONFIG_DIR/config.yml"

echo "4. DNS: cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN"
cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_DOMAIN"

echo "5. Teste: cloudflared tunnel run $TUNNEL_NAME"
echo "   Depois: curl https://$TUNNEL_DOMAIN/health"
echo
echo "Tunnel $TUNNEL_NAME -> $TUNNEL_DOMAIN -> $LOCAL_SERVICE"
