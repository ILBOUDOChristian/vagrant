#!/bin/bash
# Validation scenario V6 : panne du repartiteur lb1 et reprise VRRP.
set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;32m"
COLOR_WARN="\033[0;33m"
COLOR_ERROR="\033[0;31m"

VIP_IP="${1:-192.168.62.5}"
URL="http://${VIP_IP}:80/info"

echo "========================================================================"
echo "TEST SCÉNARIO V6 : Panne du répartiteur lb1 et bascule VRRP vers lb2"
echo "========================================================================"

echo "1. Vérification que l'adresse IP virtuelle $VIP_IP répond..."
HTTP_INIT=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || true)
if [ "$HTTP_INIT" != "200" ]; then
    echo -e "${COLOR_WARN}Note : Ce scénario nécessite que l'extension E1 soit activée (ACTIVER_EXTENSION_E1=true).${COLOR_RESET}"
    echo -e "${COLOR_ERROR}Erreur : La VIP $VIP_IP ne répond pas en HTTP 200 (reçu: $HTTP_INIT).${COLOR_RESET}"
    exit 1
fi

echo "2. Simulation de la panne du répartiteur actif : arrêt de lb1..."
DEBUT=$(date +%s%N)
vagrant halt lb1

echo "3. Mesure du temps de reprise sur la VIP $VIP_IP..."
ATTENTE=0
MAX_ATTENTE=10
REPRISE=0

while [ $ATTENTE -lt $MAX_ATTENTE ]; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 "$URL" || true)
    if [ "$CODE" = "200" ]; then
        FIN=$(date +%s%N)
        REPRISE=$(( (FIN - DEBUT) / 1000000 ))
        break
    fi
    sleep 0.5
    ATTENTE=$((ATTENTE + 1))
done

echo "========================================================================"
if [ $REPRISE -gt 0 ]; then
    TEMPS_SEC=$((REPRISE / 1000)).$((REPRISE % 1000))
    echo -e "${COLOR_INFO}SUCCÈS V6 : Service rétabli via lb2 en ${TEMPS_SEC}s (objectif < 5s) !${COLOR_RESET}"
    echo "Redémarrage de lb1 pour rétablir la redondance..."
    vagrant up lb1
    exit 0
else
    echo -e "${COLOR_ERROR}ÉCHEC V6 : Le service n'a pas repris sur la VIP après 5 secondes.${COLOR_RESET}"
    vagrant up lb1
    exit 1
fi
