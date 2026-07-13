#!/usr/bin/env bash
# setup-base.sh — Prerequisiti Debian 13 comuni a tutte le VM del lab
# Eseguire come root su ogni VM dopo l'installazione base.
# Uso: sudo bash setup-base.sh
set -euo pipefail

echo "==> Aggiornamento sistema"
apt update && apt -y full-upgrade

echo "==> Installazione pacchetti base"
apt -y install curl ca-certificates gnupg iproute2 tcpdump net-tools \
               htop vim less ufw sudo

echo "==> sysctl — parametri di rete HAProxy"
cat > /etc/sysctl.d/99-haproxy.conf <<'EOF'
# HAProxy e' un proxy, non un router
net.ipv4.ip_forward = 0

net.core.somaxconn = 20000
net.ipv4.tcp_max_syn_backlog = 20000
net.ipv4.ip_local_port_range = 1024 65000
EOF
sysctl --system

echo "==> Installazione Docker (repository ufficiale)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
docker version

echo "==> Setup base completato. Eseguire ora lo script specifico per il ruolo."
