#!/bin/bash
# Scénario V1 — Vérification de la répartition de charge (20 requêtes /info)
# Objectif : vérifier que les serveurs applicatifs se partagent la charge
# et que l'écart entre le plus et le moins sollicité est strictement inférieur à 20%
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8080}"
NB_REQUETES=20
declare -A COMPTEURS
ERREURS=0

echo "========================================================================"
echo "SCÉNARIO V1 — Répartition de charge sur 20 appels consécutifs à /info"
echo "Cible : ${BASE_URL}/info"
echo "========================================================================"

for i in $(seq 1 $NB_REQUETES); do
    RESP=$(curl -s --connect-timeout 2 "${BASE_URL}/info" || echo "")
    HOTE=$(echo "$RESP" | grep -o '"hostname": *"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "")
    if [ -n "$HOTE" ]; then
        COMPTEURS["$HOTE"]=$((${COMPTEURS["$HOTE"]:-0} + 1))
        echo "Requête $i -> $HOTE"
    else
        ERREURS=$((ERREURS + 1))
        echo "Requête $i -> ERREUR HTTP"
    fi
    sleep 0.1
done

echo "------------------------------------------------------------------------"
echo "Synthèse des sollicitations :"
MAX_VAL=0
MIN_VAL=999

for h in "${!COMPTEURS[@]}"; do
    val=${COMPTEURS["$h"]}
    echo "  - $h : $val requêtes"
    if [ "$val" -gt "$MAX_VAL" ]; then MAX_VAL=$val; fi
    if [ "$val" -lt "$MIN_VAL" ]; then MIN_VAL=$val; fi
done
echo "Erreurs constatées : $ERREURS"

if [ "$ERREURS" -gt 0 ]; then
    echo "ÉCHEC V1 : $ERREURS requête(s) ont échoué." >&2
    exit 1
fi

NB_SERVEURS=${#COMPTEURS[@]}
if [ "$NB_SERVEURS" -lt 2 ]; then
    echo "ÉCHEC V1 : Moins de 2 serveurs ont répondu." >&2
    exit 1
fi

# Calcul de l'écart relatif (seuil imposé par le Dr SOMDA : < 20%)
ECART=$((MAX_VAL - MIN_VAL))
POURCENTAGE=$(awk -v e="$ECART" -v tot="$NB_REQUETES" 'BEGIN { printf "%.1f", (e / tot) * 100 }')
echo "Écart entre le plus et le moins sollicité : $ECART requêtes ($POURCENTAGE%)"

if awk -v p="$POURCENTAGE" 'BEGIN { exit (p <= 20.0) ? 0 : 1 }'; then
    echo "SUCCÈS V1 : Répartition équilibrée (écart $POURCENTAGE% <= 20%)."
    exit 0
else
    echo "ÉCHEC V1 : L'écart dépasse le seuil de 20% fixé par le sujet." >&2
    exit 1
fi
