# HAProxy HA — Load Balancing in Alta Affidabilità per Citrix StoreFront

Coppia di load balancer HAProxy in HA (keepalived/VRRP) posizionata tra un **Citrix NetScaler** e due server **IIS/StoreFront**.

## Architettura

```
Client (HTTPS)
      │
      ▼
 Citrix NetScaler  ── termina TLS ──►  HTTP
      │
      ▼  http://<VIP_IP>:80
 ┌─────────────────────────────────────────┐
 │   IP Virtuale (VIP) — keepalived VRRP   │
 │   montato sul nodo MASTER corrente      │
 └──────┬──────────────────────┬───────────┘
 normale│                      │failover
        ▼                      ▼
┌────────────────┐   ┌─────────────────┐
│  nodo1 MASTER  │   │  nodo2 BACKUP   │
│  prio 110      │   │  prio 100       │
└────────┬───────┘   └────────┬────────┘
         └──────────┬──────────┘
                    │  mode http · roundrobin · cookie SF_STICK
                    ▼
         ┌──────────────────────────────┐
         │  StoreFront-1  :80           │
         │  StoreFront-2  :80           │
         └──────────────────────────────┘
```

**Il TLS è terminato sul NetScaler.** Il traffico interno viaggia in HTTP.

## Variabili da configurare

Prima del deploy sostituire i placeholder nei file di configurazione:

| Placeholder | Descrizione |
|---|---|
| `<NODE1_MGMT_IP>` | IP di ens192 sul nodo 1 (rete frontend/gestione) |
| `<NODE2_MGMT_IP>` | IP di ens192 sul nodo 2 |
| `<VIP_IP>` | IP virtuale gestito da keepalived |
| `<GATEWAY_IP>` | Gateway della rete frontend |
| `<NODE1_BACKEND_IP>` | IP di ens224 sul nodo 1 (rete backend) |
| `<NODE2_BACKEND_IP>` | IP di ens224 sul nodo 2 |
| `<STOREFRONT1_IP>` | IP del primo server StoreFront/IIS |
| `<STOREFRONT2_IP>` | IP del secondo server StoreFront/IIS |
| `<VRRP_PASSWORD>` | Password VRRP (max 8 caratteri, identica sui due nodi) |
| `<STATS_PASSWORD>` | Password pagina statistiche HAProxy |

## Struttura

```
conf/
├── nodo1/                    # filesystem nodo 1 (MASTER)
│   ├── opt/haproxy/
│   │   ├── haproxy.cfg
│   │   ├── docker-compose.yml
│   │   └── validate-nodo1.py
│   └── etc/
│       ├── keepalived/keepalived.conf
│       ├── keepalived/check_haproxy.sh
│       ├── network/interfaces
│       └── sysctl.d/99-haproxy.conf
└── nodo2/                    # filesystem nodo 2 (BACKUP)
    └── (stessa struttura)
```

## Deploy

```bash
# Su ogni nodo: copia il contenuto della cartella nodo corrispondente nella root
sudo cp -r conf/nodo1/* /   # su nodo 1
sudo cp -r conf/nodo2/* /   # su nodo 2

# Permessi script keepalived
sudo chmod 0700 /etc/keepalived/check_haproxy.sh

# Valida HAProxy
cd /opt/haproxy
sudo docker run --rm \
  -v "$PWD/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
  haproxy:3.0 haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Avvia HAProxy
sudo docker compose up -d

# Avvia keepalived (prima il nodo 1 / MASTER)
sudo keepalived -t -f /etc/keepalived/keepalived.conf
sudo systemctl enable --now keepalived

# Verifica VIP (solo sul MASTER)
ip -br addr show ens192
```

## Firewall (UFW)

```bash
# ⚠️ Aggiungere SSH PRIMA di ufw enable
sudo ufw allow in on ens192 to any port 22 proto tcp
sudo ufw allow in on ens192 to any port 80 proto tcp
sudo ufw allow in on ens224 to any port 8404 proto tcp

# Nodo 1: permetti VRRP dal peer (nodo 2)
sudo ufw allow in on ens192 from <NODE2_MGMT_IP> proto vrrp

# Nodo 2: permetti VRRP dal peer (nodo 1)
sudo ufw allow in on ens192 from <NODE1_MGMT_IP> proto vrrp

sudo ufw enable
```

## Stack

- **OS**: Debian 13 (trixie)
- **HAProxy**: `haproxy:3.0` in Docker (`network_mode: host`)
- **keepalived**: pacchetto nativo Debian 2.3.x
- **VRRP**: unicast, `virtual_router_id 51`

## Validazione

```bash
sudo python3 conf/nodo1/opt/haproxy/validate-nodo1.py   # su nodo 1
sudo python3 conf/nodo2/opt/haproxy/validate-nodo2.py   # su nodo 2
```

## Note Citrix StoreFront

Con SSL offload sul NetScaler è necessario:
- Configurare StoreFront per SSL offloading
- Il **Base URL** deve essere l'FQDN pubblico del NetScaler (non l'IP del VIP)
- I due StoreFront devono essere nello stesso **Server Group**
- La sticky session (`cookie SF_STICK`) è obbligatoria in configurazione multi-server
