# HAProxy HA — Lab VMware Workstation

Tre VM Debian 13 per testare HAProxy HA con keepalived/VRRP in locale.

| VM | Ruolo | RAM | NIC |
|---|---|---|---|
| `lab-haproxy-01` | MASTER | 512 MB | ens192 (MGMT) + ens224 (backend) |
| `lab-haproxy-02` | BACKUP | 512 MB | ens192 (MGMT) + ens224 (backend) |
| `lab-web` | Backend test | 256 MB | ens224 (backend) |

```
              ┌──────────────────────────────────────┐
              │   VIP <VIP_IP>  — keepalived VRRP     │
              └──────┬────────────────────────┬───────┘
         normale     │                        │  failover
                     ▼                        ▼
          ┌──────────────────┐    ┌───────────────────┐
          │ lab-haproxy-01   │    │ lab-haproxy-02    │
          │ MASTER  prio 110 │    │ BACKUP  prio 100  │
          └────────┬─────────┘    └─────────┬─────────┘
                   └──────────┬─────────────┘
                              │  mode http · cookie SF_STICK
                              ▼
                   ┌──────────────────────┐
                   │  lab-web:8081  (sf1) │
                   │  lab-web:8082  (sf2) │
                   └──────────────────────┘
```

## Script disponibili

| Script | Da eseguire su | Descrizione |
|---|---|---|
| `setup-base.sh` | tutte e 3 le VM | Aggiorna Debian, installa Docker e dipendenze base |
| `setup-haproxy-node.sh` | haproxy-01, haproxy-02 | Installa keepalived, pull immagine Docker |
| `setup-webserver.sh` | lab-web | Avvia due server HTTP di test su :8081 e :8082 |
| `install-ha-package.sh` | haproxy-01, haproxy-02 | Installa e configura i file HA dal repo |

## Procedura

### 1. Tutte e 3 le VM — setup base
```bash
sudo bash lab/setup-base.sh
```

### 2. lab-web — web server di test
```bash
sudo bash lab/setup-webserver.sh
# annota l'IP mostrato a fine script (es. 192.168.175.100)
```

### 3. lab-haproxy-01 e lab-haproxy-02 — preparazione nodo
```bash
sudo bash lab/setup-haproxy-node.sh
```

### 4. lab-haproxy-01 — installa configurazione HA (Nodo 1, MASTER)
```bash
sudo bash lab/install-ha-package.sh \
  --node 1 \
  --node1-mgmt-ip    <NODE1_MGMT_IP> \
  --node2-mgmt-ip    <NODE2_MGMT_IP> \
  --vip              <VIP_IP> \
  --gateway          <GATEWAY_IP> \
  --node1-backend-ip <NODE1_BACKEND_IP> \
  --node2-backend-ip <NODE2_BACKEND_IP> \
  --sf1-ip           <STOREFRONT1_IP> \
  --sf2-ip           <STOREFRONT2_IP> \
  --vrrp-password    <VRRP_PASSWORD> \
  --stats-password   <STATS_PASSWORD>

# Avvia keepalived sul MASTER per primo
sudo systemctl enable --now keepalived
ip -br addr show ens192   # deve mostrare il VIP
```

### 5. lab-haproxy-02 — installa configurazione HA (Nodo 2, BACKUP)
```bash
sudo bash lab/install-ha-package.sh --node 2 [stessi parametri di sopra]
sudo systemctl enable --now keepalived
```

### 6. Test bilanciamento e failover
```bash
# Dal Nodo 1: verifica VIP e bilanciamento
curl http://<VIP_IP>/    # risponde sf1 o sf2
curl http://<VIP_IP>/    # cambia al secondo accesso (prima del cookie)

# Pagina stats
# http://<NODE1_BACKEND_IP>:8404/stats

# Test failover: ferma HAProxy sul MASTER
sudo docker compose -f /opt/haproxy/docker-compose.yml stop haproxy
# Il VIP deve passare al Nodo 2 entro ~4 secondi
ip -br addr show ens192   # su Nodo 2: deve comparire il VIP
```

