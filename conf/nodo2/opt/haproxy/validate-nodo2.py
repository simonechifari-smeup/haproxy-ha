#!/usr/bin/env python3
"""
validate-nodo2.py — Validazione configurazione nodo 1 (MASTER)
Adattare le variabili nella sezione "Valori attesi" all'ambiente reale.
Eseguire come root sul server: sudo python3 validate-nodo2.py
"""

import os, subprocess, sys, re

# ── Colori ANSI ───────────────────────────────────────────────────────────────
GRN = "\033[92m"; RED = "\033[91m"; YLW = "\033[93m"; RST = "\033[0m"; BLD = "\033[1m"
def ok(msg):   print(f"  {GRN}✓{RST} {msg}")
def fail(msg): print(f"  {RED}✗{RST} {msg}"); results.append(False)
def warn(msg): print(f"  {YLW}!{RST} {msg}")
def section(t): print(f"\n{BLD}{'─'*60}\n  {t}\n{'─'*60}{RST}")
results = []

# ── Valori attesi — ADATTARE ALL'AMBIENTE ─────────────────────────────────────
NODE         = "nodo2"
MGMT_NIC     = "ens192"          # NIC rete frontend/gestione
BACKEND_NIC  = "ens224"          # NIC rete backend
NODE1_IP     = "<NODE2_MGMT_IP>"
NODE2_IP     = "<NODE1_MGMT_IP>"
VIP          = "<VIP_IP>"
GATEWAY      = "<GATEWAY_IP>"
BACKEND_IP   = "<NODE2_BACKEND_IP>"
SF1_IP       = "<STOREFRONT1_IP>"
SF2_IP       = "<STOREFRONT2_IP>"
VRRP_ROLE    = "BACKUP"
PRIORITY     = "100"
ROUTER_ID    = "HAPROXY_NODE2"
UFW_PEER     = NODE2_IP          # VRRP accettato dal peer

FILES = {
    "haproxy.cfg":     "/opt/haproxy/haproxy.cfg",
    "compose":         "/opt/haproxy/docker-compose.yml",
    "keepalived.conf": "/etc/keepalived/keepalived.conf",
    "check.sh":        "/etc/keepalived/check_haproxy.sh",
    "interfaces":      "/etc/network/interfaces",
    "sysctl":          "/etc/sysctl.d/99-haproxy.conf",
}

def read(p):
    try:
        with open(p) as f: return f.read()
    except Exception as e:
        fail(f"Impossibile leggere {p}: {e}"); return ""

def check(cond, ok_m, fail_m):
    if cond: ok(ok_m)
    else: fail(fail_m)

# 1. Esistenza file
section("1. Esistenza file")
for label, path in FILES.items():
    if os.path.exists(path): ok(path)
    else: fail(f"MANCANTE: {path}")

# 2. haproxy.cfg
section("2. haproxy.cfg — contenuto")
cfg = read(FILES["haproxy.cfg"])
if cfg:
    cfg_norm = re.sub(r'[ \t]+', ' ', cfg)
    check("mode http"              in cfg_norm, "mode http",               "mode http non trovato")
    check(f"bind 0.0.0.0:80"      in cfg_norm, "bind 0.0.0.0:80",         "bind :80 non trovato")
    check("option forwardfor"      in cfg_norm, "option forwardfor",       "option forwardfor non trovato")
    check("cookie SF_STICK insert" in cfg_norm, "cookie SF_STICK insert",  "sticky session SF_STICK non trovata")
    check("user haproxy"           in cfg_norm, "user haproxy",            "user haproxy non trovato")
    check("group haproxy"          in cfg_norm, "group haproxy",           "group haproxy non trovato")
    check(f"{SF1_IP}:80"           in cfg,      f"backend sf1 {SF1_IP}:80","IP StoreFront1 non trovato")
    check(f"{SF2_IP}:80"           in cfg,      f"backend sf2 {SF2_IP}:80","IP StoreFront2 non trovato")
    check("option tcp-check" not in cfg_norm,   "option tcp-check assente","ATTENZIONE: option tcp-check con mode http")

# 3. Sintassi haproxy (docker)
section("3. haproxy.cfg — sintassi")
try:
    r = subprocess.run(["docker","run","--rm",
        "-v","/opt/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro",
        "haproxy:3.0","haproxy","-c","-f","/usr/local/etc/haproxy/haproxy.cfg"],
        capture_output=True, text=True, timeout=30)
    check(r.returncode == 0, "Sintassi haproxy.cfg valida", f"Errore:\n{r.stderr.strip()}")
except FileNotFoundError: warn("Docker non trovato — skip")
except subprocess.TimeoutExpired: warn("Timeout — skip")

# 4. docker-compose.yml
section("4. docker-compose.yml")
dc = read(FILES["compose"])
if dc:
    check("haproxy:3.0"             in dc, "image haproxy:3.0",          "image non trovata")
    check("network_mode: host"      in dc, "network_mode: host",         "network_mode: host non trovato")
    check("user: root"              in dc, "user: root",                 "user: root non trovato")
    check("restart: unless-stopped" in dc, "restart: unless-stopped",    "restart policy non trovata")
    try:
        import yaml; yaml.safe_load(dc); ok("YAML valido")
    except ImportError: warn("PyYAML non installato — skip")
    except Exception as e: fail(f"YAML non valido: {e}")

# 5. keepalived.conf
section("5. keepalived.conf")
kp = read(FILES["keepalived.conf"])
if kp:
    check(f"router_id {ROUTER_ID}"        in kp, f"router_id {ROUTER_ID}",           f"atteso: {ROUTER_ID}")
    check(f"state             {VRRP_ROLE}" in kp, f"state {VRRP_ROLE}",               f"atteso: {VRRP_ROLE}")
    check(f"priority          {PRIORITY}"  in kp, f"priority {PRIORITY}",             f"attesa: {PRIORITY}")
    check(f"interface         {MGMT_NIC}"  in kp, f"interface {MGMT_NIC}",            f"attesa: {MGMT_NIC}")
    check("virtual_router_id 51"           in kp, "virtual_router_id 51",             "virtual_router_id 51 non trovato")
    check(f"unicast_src_ip  {NODE1_IP}"    in kp, f"unicast_src_ip {NODE1_IP}",       f"atteso: {NODE1_IP}")
    check(NODE2_IP                         in kp, f"unicast_peer {NODE2_IP}",         f"peer atteso: {NODE2_IP}")
    check(f"{VIP}/24 dev {MGMT_NIC}"       in kp, f"VIP {VIP}/24 dev {MGMT_NIC}",    "VIP non trovato")
    check("weight   -20"                   in kp, "weight -20",                       "weight -20 non trovato")

# 6. Sintassi keepalived
section("6. keepalived.conf — sintassi")
try:
    r = subprocess.run(["keepalived","-t","-f","/etc/keepalived/keepalived.conf"],
        capture_output=True, text=True, timeout=10)
    out = (r.stdout+r.stderr).strip()
    if r.returncode == 0 and "error" not in out.lower(): ok("Sintassi keepalived valida")
    elif "error" in out.lower(): fail(f"Errori keepalived:\n{out}")
    else: ok("Sintassi keepalived valida")
except FileNotFoundError: warn("keepalived non trovato — skip")
except subprocess.TimeoutExpired: warn("Timeout — skip")

# 7. check_haproxy.sh
section("7. check_haproxy.sh")
sh = read(FILES["check.sh"])
if sh:
    check("127.0.0.1/80" in sh, "porta 80 nel check script", "porta 80 non trovata")
    check("bash -c"       in sh, "bash -c usato",             "bash -c non trovato")
    try:
        mode = oct(os.stat(FILES["check.sh"]).st_mode)[-3:]
        check(mode == "700", f"permessi {mode} (atteso 700)", f"permessi {mode} — atteso 700")
    except Exception as e: warn(f"Permessi: {e}")

# 8. Interfacce di rete
section("8. /etc/network/interfaces")
iface = read(FILES["interfaces"])
if iface:
    check(NODE1_IP    in iface, f"{MGMT_NIC} = {NODE1_IP}",  f"IP atteso: {NODE1_IP}")
    check(BACKEND_IP  in iface, f"{BACKEND_NIC} = {BACKEND_IP}", f"IP atteso: {BACKEND_IP}")
    check(GATEWAY     in iface, f"gateway = {GATEWAY}",      f"gateway atteso: {GATEWAY}")

section("8b. IP live")
try:
    r  = subprocess.run(["ip","-br","addr","show",MGMT_NIC],    capture_output=True, text=True)
    r2 = subprocess.run(["ip","-br","addr","show",BACKEND_NIC], capture_output=True, text=True)
    check(NODE1_IP   in r.stdout,  f"{MGMT_NIC} ha {NODE1_IP} (live)",    f"{MGMT_NIC}: {r.stdout.strip()}")
    check(BACKEND_IP in r2.stdout, f"{BACKEND_NIC} ha {BACKEND_IP} (live)",f"{BACKEND_NIC}: {r2.stdout.strip()}")
    if VIP in r.stdout: ok(f"VIP {VIP} presente (failover attivo?)")
    else: warn(f"VIP {VIP} non presente — keepalived non avviato (corretto per BACKUP")
except FileNotFoundError: warn("Comando 'ip' non trovato")

# 9. sysctl
section("9. sysctl")
sc = read(FILES["sysctl"])
if sc:
    check("net.ipv4.ip_forward = 0"             in sc, "ip_forward = 0",            "ip_forward errato")
    check("net.core.somaxconn = 20000"           in sc, "somaxconn = 20000",         "somaxconn non trovato")
    check("net.ipv4.tcp_max_syn_backlog = 20000" in sc, "tcp_max_syn_backlog = 20000","tcp_max_syn_backlog non trovato")

# 10. Servizi
section("10. Stato servizi")
for svc in ["docker","keepalived"]:
    r  = subprocess.run(["systemctl","is-active", svc], capture_output=True, text=True)
    r2 = subprocess.run(["systemctl","is-enabled",svc], capture_output=True, text=True)
    check(r.stdout.strip()  == "active",  f"{svc} attivo",           f"{svc} NON attivo")
    check(r2.stdout.strip() == "enabled", f"{svc} abilitato al boot",f"{svc} NON abilitato al boot")
r = subprocess.run(["docker","inspect","--format","{{.State.Status}}","haproxy"], capture_output=True, text=True)
check(r.stdout.strip() == "running", "container haproxy running", f"container: {r.stdout.strip()}")
r = subprocess.run(["docker","inspect","--format","{{.State.Health.Status}}","haproxy"], capture_output=True, text=True)
s = r.stdout.strip()
if s == "healthy": ok("container haproxy healthy")
elif s == "": warn("healthcheck non disponibile")
else: fail(f"container haproxy: {s}")

# 11. UFW
section("11. UFW")
try:
    r = subprocess.run(["ufw","status","verbose"], capture_output=True, text=True)
    u = r.stdout
    check("Status: active" in u, "UFW attivo", "UFW non attivo")
    check("80/tcp" in u and MGMT_NIC in u,    f"regola tcp/80 su {MGMT_NIC}",    f"MANCANTE: ufw allow in on {MGMT_NIC} to any port 80 proto tcp")
    check("8404/tcp" in u and BACKEND_NIC in u,f"regola tcp/8404 su {BACKEND_NIC}",f"MANCANTE: ufw allow in on {BACKEND_NIC} to any port 8404 proto tcp")
    check(UFW_PEER in u and "vrrp" in u.lower(),f"regola VRRP da {UFW_PEER}",    f"MANCANTE: ufw allow in on {MGMT_NIC} from {UFW_PEER} proto vrrp")
except FileNotFoundError: warn("ufw non installato — skip")

# Riepilogo
print(f"\n{'═'*60}")
failures = results.count(False)
if failures == 0: print(f"{GRN}{BLD}  TUTTO OK — {NODE} validato con successo{RST}")
else: print(f"{RED}{BLD}  {failures} ERRORE/I — verificare i punti marcati con ✗{RST}")
print(f"{'═'*60}\n")
sys.exit(0 if failures == 0 else 1)
