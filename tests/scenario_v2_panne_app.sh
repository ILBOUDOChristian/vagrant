#!/bin/bash
# Scénario V2 — Résilience applicative : éviction d'un serveur défaillant
#
# Objectif : confirmer que HAProxy écarte app1 en moins de 5 secondes
# lorsque son service est arrêté, et que les requêtes continuent d'aboutir.
#
# Préconditions : vagrant up complet, app1 et app2 en running.
# Résultat attendu :
#   - Toutes les requêtes avant la panne réussissent.
#   - Après l'arrêt de app1, les requêtes continuent sur app2 en < 5s.
#   - La durée d'indisponibilité est mesurée et affichée.
#
# Commande : bash tests/scenario_v2_panne_app.sh
set -euo pipefail

BASE_URL="http://127.0.0.1:8080"
SEUIL_SECONDES=5

requete_info() {
    curl -sf --max-time 2 "${BASE_URL}/info" 2>/dev/null
}

echo "V2 — Test de résilience applicative"
echo ""
echo "Étape 1 : vérification que les deux serveurs répondent..."
AVANT=$(requete_info) || { echo "ÉCHEC : le service ne répond pas avant le test." >&2; exit 1; }
echo "  Serveur actif avant test : $(echo "$AVANT" | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])")"

echo ""
echo "Étape 2 : arrêt du service applicatif sur app1..."
vagrant ssh app1 -c "sudo systemctl stop resultats-bf" 2>/dev/null
DEBUT_PANNE_MS=$(($(date +%s%3N)))
echo "  Service app1 arrêté à $(date +%H:%M:%S.%3N)"

echo ""
echo "Étape 3 : envoi continu de requêtes jusqu'à détection de la reprise..."
PREMIERE_REUSSITE_MS=0
NBECHECS=0
for i in $(seq 1 30); do
    if REPONSE=$(requete_info 2>/dev/null); then
        HOTE=$(echo "$REPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])" 2>/dev/null || echo "?")
        if [ "$HOTE" = "app2" ]; then
            PREMIERE_REUSSITE_MS=$(($(date +%s%3N)))
            echo "  Requête ${i} → ${HOTE} ✓"
            break
        fi
    else
        NBECHECS=$((NBECHECS + 1))
        echo "  Requête ${i} : timeout (${NBECHECS} échec(s) consécutifs)"
    fi
    sleep 0.5
done

echo ""
if [ "$PREMIERE_REUSSITE_MS" -eq 0 ]; then
    echo "ÉCHEC : app2 n'a pas pris le relais en 15 secondes." >&2
    vagrant ssh app1 -c "sudo systemctl start resultats-bf" 2>/dev/null || true
    exit 1
fi

DUREE_MS=$((PREMIERE_REUSSITE_MS - DEBUT_PANNE_MS))
DUREE_SEC=$(awk -v ms="$DUREE_MS" 'BEGIN { printf "%.2f", ms / 1000 }')
echo "Durée d'éviction HAProxy : ${DUREE_SEC} secondes"

vagrant ssh app1 -c "sudo systemctl start resultats-bf" 2>/dev/null
echo "  Service app1 redémarré."

if awk -v d="$DUREE_SEC" -v s="$SEUIL_SECONDES" 'BEGIN { exit (d > s) ? 0 : 1 }'; then
    echo "ÉCHEC : l'éviction a pris ${DUREE_SEC}s (seuil : ${SEUIL_SECONDES}s)." >&2
    exit 1
fi

echo "OK : éviction en ${DUREE_SEC}s < ${SEUIL_SECONDES}s. Exigence R4 respectée."
