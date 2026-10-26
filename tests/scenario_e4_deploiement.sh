#!/bin/bash
# Validation scenario E4 : mise a jour complete pendant un test de charge.
set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;32m"
COLOR_WARN="\033[0;33m"
COLOR_ERROR="\033[0;31m"

BASE_URL="${URL_API_BASE:?URL_API_BASE absent — ajoutez-le dans votre fichier .env (voir .env.exemple)}"
URL="${BASE_URL}/info"
LOG_REQUETES="/tmp/e4_charge.log"

echo "========================================================================"
echo "TEST SCÉNARIO E4 : Déploiement sans coupure sous charge active"
echo "========================================================================"

# Vérifier que le service répond
HTTP_INIT=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || true)
if [ "$HTTP_INIT" != "200" ]; then
    echo -e "${COLOR_ERROR}Erreur : Le service ne répond pas sur $URL (code $HTTP_INIT).${COLOR_RESET}"
    exit 1
fi

echo "1. Lancement d'un flux continu de requêtes HTTP en arrière-plan..."
rm -f "$LOG_REQUETES"
(
    while true; do
        curl -s -o /dev/null -w "%{http_code}\n" "$URL" >> "$LOG_REQUETES" 2>&1 || echo "000" >> "$LOG_REQUETES"
        sleep 0.05
    done
) &
PID_CHARGE=$!

trap "kill -9 $PID_CHARGE 2>/dev/null || true" EXIT

echo "Flux de requêtes démarré (PID $PID_CHARGE). Attente de 3 secondes..."
sleep 3

echo "2. Déclenchement de la mise à jour sans coupure sur le répartiteur..."
vagrant ssh lb1 -c "sudo bash /vagrant/scripts/deploiement_sans_coupure.sh"

echo "3. Arrêt du test de charge et analyse des résultats..."
kill -9 $PID_CHARGE 2>/dev/null || true
trap - EXIT

TOTAL_REQUETES=$(wc -l < "$LOG_REQUETES" || echo 0)
REQUETES_OK=$(grep -c "^200$" "$LOG_REQUETES" || echo 0)
REQUETES_KO=$((TOTAL_REQUETES - REQUETES_OK))

echo "========================================================================"
echo "BILAN DE L'EXTENSION E4 :"
echo "  - Total de requêtes envoyées pendant la mise à jour : $TOTAL_REQUETES"
echo "  - Requêtes réussies (HTTP 200)                      : $REQUETES_OK"
echo "  - Requêtes en erreur (HTTP 5xx / échec réseau)       : $REQUETES_KO"
echo "========================================================================"

if [ "$REQUETES_KO" -eq 0 ] && [ "$TOTAL_REQUETES" -gt 0 ]; then
    echo -e "${COLOR_INFO}SUCCÈS E4 : Aucune requête perdue pendant la mise à jour complète ! (Disponibilité 100%)${COLOR_RESET}"
    exit 0
else
    echo -e "${COLOR_ERROR}ÉCHEC E4 : $REQUETES_KO requêtes ont échoué pendant le déploiement.${COLOR_RESET}"
    exit 1
fi
