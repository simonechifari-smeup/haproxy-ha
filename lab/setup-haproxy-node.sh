#!/usr/bin/env bash
# setup-haproxy-node.sh — Installa keepalived e prepara le directory per i nodi HAProxy
# Eseguire come root DOPO setup-base.sh.
# Uso: sudo bash setup-haproxy-node.sh
set -euo pipefail

echo "==> Installazione keepalived"
apt -y install keepalived
# Non avviare ancora: prima va configurato (usa install-ha-package.sh)
systemctl disable keepalived 2>/dev/null || true
systemctl stop keepalived 2>/dev/null || true

echo "==> Creazione directory di lavoro HAProxy"
mkdir -p /opt/haproxy

echo "==> Pull immagine Docker HAProxy 3.0"
docker pull haproxy:3.0

echo "==> Verifica keepalived"
keepalived --version 2>&1 | head -1

echo ""
echo "==> Nodo HAProxy pronto."
echo "    Prossimo passo: eseguire install-ha-package.sh per applicare la configurazione."
