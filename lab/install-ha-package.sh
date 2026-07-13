#!/usr/bin/env bash
# install-ha-package.sh — Installa la configurazione HA dal repo sui nodi HAProxy
# Sostituisce i placeholder con i valori reali e copia i file nelle posizioni corrette.
# Eseguire come root DOPO setup-haproxy-node.sh.
#
# Uso:
#   sudo bash install-ha-package.sh --node 1 \
#     --node1-mgmt-ip  192.168.50.30 \
#     --node2-mgmt-ip  192.168.50.31 \
#     --vip            192.168.50.20 \
#     --gateway        192.168.50.254 \
#     --node1-backend-ip 192.168.175.201 \
#     --node2-backend-ip 192.168.175.202 \
#     --sf1-ip         192.168.175.25 \
#     --sf2-ip         192.168.175.26 \
#     --vrrp-password  MyPass1! \
#     --stats-password MyStatsPass123!
set -euo pipefail

# ── Parsing argomenti ──────────────────────────────────────────────────────────
usage() {
  echo "Uso: $0 --node <1|2> --node1-mgmt-ip <IP> --node2-mgmt-ip <IP>"
  echo "         --vip <IP> --gateway <IP>"
  echo "         --node1-backend-ip <IP> --node2-backend-ip <IP>"
  echo "         --sf1-ip <IP> --sf2-ip <IP>"
  echo "         --vrrp-password <PASS> --stats-password <PASS>"
  exit 1
}

NODE=""
NODE1_MGMT=""
NODE2_MGMT=""
VIP=""
GATEWAY=""
NODE1_BACKEND=""
NODE2_BACKEND=""
SF1_IP=""
SF2_IP=""
VRRP_PASS=""
STATS_PASS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)            NODE="$2";            shift 2 ;;
    --node1-mgmt-ip)   NODE1_MGMT="$2";      shift 2 ;;
    --node2-mgmt-ip)   NODE2_MGMT="$2";      shift 2 ;;
    --vip)             VIP="$2";             shift 2 ;;
    --gateway)         GATEWAY="$2";         shift 2 ;;
    --node1-backend-ip) NODE1_BACKEND="$2";  shift 2 ;;
    --node2-backend-ip) NODE2_BACKEND="$2";  shift 2 ;;
    --sf1-ip)          SF1_IP="$2";          shift 2 ;;
    --sf2-ip)          SF2_IP="$2";          shift 2 ;;
    --vrrp-password)   VRRP_PASS="$2";       shift 2 ;;
    --stats-password)  STATS_PASS="$2";      shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$NODE" || -z "$NODE1_MGMT" || -z "$NODE2_MGMT" || -z "$VIP" || \
   -z "$GATEWAY" || -z "$NODE1_BACKEND" || -z "$NODE2_BACKEND" || \
   -z "$SF1_IP" || -z "$SF2_IP" || -z "$VRRP_PASS" || -z "$STATS_PASS" ]] && usage

[[ "$NODE" != "1" && "$NODE" != "2" ]] && { echo "ERRORE: --node deve essere 1 o 2"; exit 1; }

# Imposta variabili dipendenti dal nodo
if [[ "$NODE" == "1" ]]; then
  MY_MGMT_IP="$NODE1_MGMT";   PEER_MGMT_IP="$NODE2_MGMT"
  MY_BACKEND_IP="$NODE1_BACKEND"
  VRRP_STATE="MASTER";         VRRP_PRIORITY="110"
  ROUTER_ID="HAPROXY_NODE1"
else
  MY_MGMT_IP="$NODE2_MGMT";   PEER_MGMT_IP="$NODE1_MGMT"
  MY_BACKEND_IP="$NODE2_BACKEND"
  VRRP_STATE="BACKUP";         VRRP_PRIORITY="100"
  ROUTER_ID="HAPROXY_NODE2"
fi

# Percorso del repo (directory da cui si esegue lo script)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_SRC="$REPO_DIR/conf/nodo${NODE}"

echo "==> Installazione configurazione HA — Nodo ${NODE} (${VRRP_STATE})"
echo "    Sorgente: $CONF_SRC"

# Funzione di sostituzione placeholder
substitute() {
  local content="$1"
  content="${content//<NODE1_MGMT_IP>/$NODE1_MGMT}"
  content="${content//<NODE2_MGMT_IP>/$NODE2_MGMT}"
  content="${content//<VIP_IP>/$VIP}"
  content="${content//<GATEWAY_IP>/$GATEWAY}"
  content="${content//<NODE1_BACKEND_IP>/$NODE1_BACKEND}"
  content="${content//<NODE2_BACKEND_IP>/$NODE2_BACKEND}"
  content="${content//<STOREFRONT1_IP>/$SF1_IP}"
  content="${content//<STOREFRONT2_IP>/$SF2_IP}"
  content="${content//<VRRP_PASSWORD>/$VRRP_PASS}"
  content="${content//<STATS_PASSWORD>/$STATS_PASS}"
  echo "$content"
}

install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  mkdir -p "$(dirname "$dst")"
  substitute "$(cat "$src")" > "$dst"
  chmod "$mode" "$dst"
  echo "    ✓ $dst"
}

echo ""
echo "==> /opt/haproxy/"
install_file "$CONF_SRC/opt/haproxy/haproxy.cfg"        /opt/haproxy/haproxy.cfg
install_file "$CONF_SRC/opt/haproxy/docker-compose.yml" /opt/haproxy/docker-compose.yml

echo ""
echo "==> /etc/keepalived/"
install_file "$CONF_SRC/etc/keepalived/keepalived.conf" /etc/keepalived/keepalived.conf
install_file "$CONF_SRC/etc/keepalived/check_haproxy.sh" /etc/keepalived/check_haproxy.sh 700
chown root:root /etc/keepalived/check_haproxy.sh

echo ""
echo "==> /etc/sysctl.d/"
install_file "$CONF_SRC/etc/sysctl.d/99-haproxy.conf" /etc/sysctl.d/99-haproxy.conf
sysctl --system > /dev/null

echo ""
echo "==> Validazione sintassi haproxy.cfg"
cd /opt/haproxy
docker run --rm \
  -v "$PWD/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
  haproxy:3.0 haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg \
  && echo "    ✓ Sintassi haproxy.cfg valida"

echo ""
echo "==> Validazione sintassi keepalived.conf"
keepalived -t -f /etc/keepalived/keepalived.conf \
  && echo "    ✓ Sintassi keepalived.conf valida"

echo ""
echo "==> Avvio HAProxy"
cd /opt/haproxy
docker compose up -d
docker compose ps

echo ""
echo "==> UFW — regole firewall"
ufw allow in on ens192 to any port 22   proto tcp
ufw allow in on ens192 to any port 80   proto tcp
ufw allow in on ens224 to any port 8404 proto tcp
ufw allow in on ens192 from "$PEER_MGMT_IP" proto vrrp
ufw --force enable
echo "    ✓ UFW configurato (peer VRRP: $PEER_MGMT_IP)"

echo ""
echo "==> Test health check script"
/etc/keepalived/check_haproxy.sh && echo "    ✓ check_haproxy.sh OK (exit 0)"

echo ""
echo "════════════════════════════════════════════════════"
echo "  Nodo ${NODE} (${VRRP_STATE}) installato con successo"
echo ""
echo "  Per avviare keepalived:"
echo "  sudo systemctl enable --now keepalived"
echo ""
if [[ "$NODE" == "1" ]]; then
  echo "  ⚠ Avviare prima il Nodo 1 (MASTER), poi il Nodo 2 (BACKUP)"
fi
echo "════════════════════════════════════════════════════"
