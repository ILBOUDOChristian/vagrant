#!/bin/bash
# Configuration HAProxy et Keepalived (VRRP - Extension E1)
# Généré depuis /vagrant/config/noeuds.yml (Source unique de vérité)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;32m"
COLOR_WARN="\033[0;33m"
COLOR_ERROR="\033[0;31m"

log_info()  { echo -e "${COLOR_INFO}INFO:${COLOR_RESET} $*"; }
log_warn()  { echo -e "${COLOR_WARN}WARNING:${COLOR_RESET} $*" >&2; }
log_error() { echo -e "${COLOR_ERROR}ERROR:${COLOR_RESET} $*" >&2; }

log_info "Installation de HAProxy, socat et keepalived..."
apt-get install -y --no-install-recommends haproxy socat keepalived

python3 - <<'PY'
import pathlib
import re

text = pathlib.Path("/vagrant/config/noeuds.yml").read_text(encoding="utf-8")
apps = []
current = {}
for raw in text.splitlines():
    match = re.match(r"^\s*-?\s*(nom|ip|mem|role):\s*(.+)\s*$", raw)
    if not match:
        continue
    current[match.group(1)] = match.group(2).strip().strip("\"'")
    if match.group(1) == "role":
        if current.get("role") == "app":
            apps.append(current)
        current = {}

if not apps:
    raise SystemExit("aucun nœud applicatif dans config/noeuds.yml")

# Configuration de la sonde de santé active : écarte un serveur défaillant en moins de 5 secondes (inter 2s, fall 2)
servers = "\n".join(
    f"    server {n['nom']} {n['ip']}:8000 check inter 2s fall 2 rise 2" for n in apps
)
conf = f"""global
    log /dev/log local0
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    maxconn 2048
    daemon

defaults
    log global
    mode http
    option httplog
    timeout connect 5s
    timeout client 30s
    timeout server 30s

# Généré depuis /vagrant/config/noeuds.yml
frontend fe_http
    bind *:80
    default_backend be_apps

backend be_apps
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
{servers}
"""
pathlib.Path("/etc/haproxy/haproxy.cfg.new").write_text(conf, encoding="utf-8")
PY

haproxy -c -f /etc/haproxy/haproxy.cfg.new
mv /etc/haproxy/haproxy.cfg.new /etc/haproxy/haproxy.cfg
systemctl enable haproxy
if systemctl is-active --quiet haproxy; then
  systemctl reload haproxy
else
  systemctl start haproxy
fi
systemctl is-active --quiet haproxy
log_info "HAProxy est actif avec $(grep -c '^[[:space:]]*server ' /etc/haproxy/haproxy.cfg) serveurs applicatifs."

# ==============================================================================
# Extension E1 : Configuration Keepalived / VRRP pour redondance (lb1 / lb2)
# ==============================================================================
HOTE="$(hostname)"
VIP="${RESEAU:-192.168.62}.5"
IFACE="$(ip -o route get 192.168.56.1 2>/dev/null | awk '{print $3}' || ip -o -4 route show to default | awk '{print $5}' | head -n1)"
if [ -z "$IFACE" ]; then
  IFACE="eth1"
fi

if [ "$HOTE" = "lb1" ]; then
    ETAT="MASTER"
    PRIO=101
else
    ETAT="BACKUP"
    PRIO=100
fi

if [ "${ACTIVER_EXTENSION_E1:-false}" = "true" ] || [ "$HOTE" = "lb2" ]; then
    cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id $HOTE
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_RESULTATS {
    state $ETAT
    interface $IFACE
    virtual_router_id 51
    priority $PRIO
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass VrrpBf2026
    }

    virtual_ipaddress {
        $VIP/24
    }

    track_script {
        chk_haproxy
    }
}
EOF

    if [ -n "$IFACE" ] && ip link show "$IFACE" >/dev/null 2>&1; then
        systemctl enable keepalived 2>/dev/null || true
        systemctl restart keepalived 2>/dev/null || true
        log_info "Keepalived ($ETAT) configuré sur $HOTE avec VIP $VIP (interface $IFACE)."
    else
        log_warn "Interface réseau $IFACE non prête pour Keepalived ; configuration différée."
    fi
fi

# Résumé de validation des services
echo ""
echo "================================================================================"
echo "  RÉSULTATS-BF — Statut des services sur $(hostname) :"
if systemctl is-active --quiet haproxy; then
    echo "  [OK] HAProxy : Actif (écoute sur le port 80)"
else
    echo "  [ATTENTION] HAProxy : Inactif"
fi
echo "================================================================================"
BASE_URL="${URL_API_BASE:?URL_API_BASE non défini dans l'environnement de provisionnement}"
echo ""
echo "  Accès au Portail Web : ${BASE_URL}/ "
echo "  Endpoints disponibles :"
echo "    - ${BASE_URL}/          (Portail Web Haute Disponibilité)"
echo "    - ${BASE_URL}/sante     (Sonde de santé active)"
echo "    - ${BASE_URL}/info      (Répartition Round-Robin)"
echo "    - ${BASE_URL}/resultat?matricule=BF-000006"
echo "================================================================================"
