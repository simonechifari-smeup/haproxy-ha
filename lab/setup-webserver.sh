#!/usr/bin/env bash
# setup-webserver.sh — Web server HTTP di test per il lab HAProxy
# Simula due backend StoreFront su porte diverse della stessa VM.
# Eseguire come root DOPO setup-base.sh.
# Uso: sudo bash setup-webserver.sh
set -euo pipefail

echo "==> Installazione Python3"
apt -y install python3

echo "==> Creazione directory dei due siti di test"
mkdir -p /srv/sf1 /srv/sf2

cat > /srv/sf1/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>StoreFront-1</title></head>
<body style="font-family:sans-serif;background:#e8f5e9;padding:40px">
  <h1 style="color:#2e7d32">StoreFront-1</h1>
  <p>Server: <strong>sf1</strong></p>
  <p>Porta: <strong>8081</strong></p>
</body></html>
EOF

cat > /srv/sf2/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>StoreFront-2</title></head>
<body style="font-family:sans-serif;background:#e3f2fd;padding:40px">
  <h1 style="color:#1565c0">StoreFront-2</h1>
  <p>Server: <strong>sf2</strong></p>
  <p>Porta: <strong>8082</strong></p>
</body></html>
EOF

echo "==> Creazione unit systemd per StoreFront-1 (porta 8081)"
cat > /etc/systemd/system/sf1.service <<'EOF'
[Unit]
Description=Lab StoreFront-1 HTTP server
After=network.target

[Service]
Type=simple
WorkingDirectory=/srv/sf1
ExecStart=python3 -m http.server 8081
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creazione unit systemd per StoreFront-2 (porta 8082)"
cat > /etc/systemd/system/sf2.service <<'EOF'
[Unit]
Description=Lab StoreFront-2 HTTP server
After=network.target

[Service]
Type=simple
WorkingDirectory=/srv/sf2
ExecStart=python3 -m http.server 8082
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sf1 sf2

echo "==> UFW — apertura porte 8081 e 8082"
ufw allow 8081/tcp
ufw allow 8082/tcp
ufw allow 22/tcp
ufw --force enable

echo ""
echo "==> Web server di test avviato."
WEB_IP=$(ip -br addr show | grep -v '^lo' | awk '{print $3}' | cut -d/ -f1 | head -1)
echo "    IP: ${WEB_IP}"
echo "    StoreFront-1: http://${WEB_IP}:8081"
echo "    StoreFront-2: http://${WEB_IP}:8082"
echo ""
echo "    Usa questi IP in install-ha-package.sh come STOREFRONT1_IP/STOREFRONT2_IP."
