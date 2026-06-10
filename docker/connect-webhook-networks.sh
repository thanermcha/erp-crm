#!/usr/bin/env bash
set -euo pipefail
echo "Conectando webhook-server as redes externas..."
for net in meta-agency-stack_meta_net openclaw-ai_openclaw-lan; do
  if docker network inspect "$net" &>/dev/null; then
    docker network connect "$net" webhook-server 2>/dev/null && \
      echo "  Conectado a $net" || echo "  $net ja conectado"
  else
    echo "  Rede $net nao encontrada (ignore se nao usar)"
  fi
done
