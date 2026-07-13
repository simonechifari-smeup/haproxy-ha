#!/usr/bin/env bash
# /etc/keepalived/check_haproxy.sh
# chmod 0700, chown root:root
# Ritorna 0 se HAProxy accetta connessioni TCP sulla porta 80, altrimenti 1.
# Usato da keepalived (track_script) per cedere il VIP se HAProxy non risponde.
timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/80' 2>/dev/null
