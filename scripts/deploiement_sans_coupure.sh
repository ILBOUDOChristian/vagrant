#!/bin/bash
# Extension E4 : deploiement sans coupure (rolling update)
# Retire chaque serveur applicatif de HAProxy, met a jour et reactive.
set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;32m"
COLOR_WARN="\033[0;33m"
COLOR_ERROR="\033[0;31m"

log_info()  { echo -e "${COLOR_INFO}INFO:${COLOR_RESET} $*"; }
log_warn()  { echo -e "${COLOR_WARN}WARNING:${COLOR_RESET} $*" >&2; }
log_error() { echo -e "${COLOR_ERROR}ERROR:${COLOR_RESET} $*" >&2; }

SOCKET="/run/haproxy/admin.sock"

haproxy_cmd() {
    echo "$1" | sudo socat stdio "$SOCKET"
}

if [ ! -S "$SOCKET" ]; then
    log_error "Socket administrative HAProxy introuvable : $SOCKET"
    exit 1
fi

NOEUDS_FILE="/vagrant/config/noeuds.yml"
if [ ! -f "$NOEUDS_FILE" ]; then
    log_error "Inventaire $NOEUDS_FILE introuvable."
    exit 1
fi

SERVEURS_APP=$(python3 -c "
import pathlib, re
text = pathlib.Path('$NOEUDS_FILE').read_text(encoding='utf-8')
apps = []
current = {}
for line in text.splitlines():
    m = re.match(r'^\s*-?\s*(nom|role):\s*(.+)\s*$', line)
    if m:
        current[m.group(1)] = m.group(2).strip().strip('\"\'')
        if m.group(1) == 'role':
            if current.get('role') == 'app':
                apps.append(current['nom'])
            current = {}
print(' '.join(apps))
")

if [ -z "$SERVEURS_APP" ]; then
    log_error "Aucun serveur applicatif trouvé dans l'inventaire."
    exit 1
fi

log_info "Début du déploiement sans coupure (Rolling Update) pour : $SERVEURS_APP"
DEBUT=$(date +%s%N)

for APP in $SERVEURS_APP; do
    echo "------------------------------------------------------------------------"
    log_info "Étape 1 : Passage de $APP en mode DRAIN dans HAProxy..."
    haproxy_cmd "set server be_apps/$APP state drain"
    sleep 2

    log_info "Étape 2 : Arrêt de l'envoi de nouvelles requêtes vers $APP (mode MAINT)..."
    haproxy_cmd "set server be_apps/$APP state maint"
    sleep 1

    log_info "Étape 3 : Mise à jour du code et redémarrage du service sur $APP..."
    # Exécution via SSH direct sur le réseau privé sans tolérance aux pannes silencieuses
    if [ "$(hostname)" = "$APP" ]; then
        sudo cp /vagrant/app/app.py /opt/resultats-bf/app.py
        sudo systemctl restart resultats-bf
    else
        ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$APP" \
            "sudo cp /vagrant/app/app.py /opt/resultats-bf/app.py && sudo systemctl restart resultats-bf"
    fi

    log_info "Étape 4 : Attente que la sonde /sante sur $APP réponde HTTP 200..."
    ATTENTE=0
    MAX_ATTENTE=20
    SUCCES=0
    while [ $ATTENTE -lt $MAX_ATTENTE ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$APP:8000/sante" || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            SUCCES=1
            break
        fi
        sleep 1
        ATTENTE=$((ATTENTE + 1))
    done

    if [ $SUCCES -ne 1 ]; then
        log_error "Échec de santé sur $APP après mise à jour (code: $HTTP_CODE). Annulation."
        haproxy_cmd "set server be_apps/$APP state ready"
        exit 1
    fi

    log_info "Étape 5 : Réintégration de $APP dans le cluster HAProxy..."
    haproxy_cmd "set server be_apps/$APP state ready"
    sleep 2
    log_info "$APP est mis à jour et actif dans le cluster."
done

FIN=$(date +%s%N)
DUREE=$(( (FIN - DEBUT) / 1000000 ))
echo "========================================================================"
log_info "Déploiement sans coupure terminé avec SUCCÈS en $((DUREE / 1000)).$((DUREE % 1000))s !"
echo "========================================================================"
