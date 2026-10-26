#!/bin/bash
# Scénario V3 — Test de charge : mesure du débit selon NB_APP
#
# Objectif : mesurer et comparer le débit obtenu avec 2 et 4 serveurs applicatifs.
#
# Préconditions :
#   - vagrant up avec NB_APP=2 pour la première mesure.
#   - vagrant up app3 app4 && vagrant provision lb1 pour la seconde.
#   - Apache Bench (ab) installé sur la machine hôte.
#
# Commande : bash tests/scenario_v3_charge.sh
# Les résultats sont affichés et peuvent être copiés dans le dossier d'architecture.
set -euo pipefail

BASE_URL="${URL_API_BASE:?URL_API_BASE absent — ajoutez-le dans votre fichier .env (voir .env.exemple)}"
NB_REQUETES=2000
CONCURRENCE=50
ENDPOINT="/info"

if ! command -v ab &>/dev/null; then
    echo "ERREUR : Apache Bench (ab) n'est pas installé sur la machine hôte." >&2
    echo "  Windows : installer httpd depuis https://www.apachelounge.com" >&2
    echo "  Linux/WSL : sudo apt install apache2-utils" >&2
    exit 1
fi

echo "V3 — Test de charge avec Apache Bench"
echo "  Endpoint : ${BASE_URL}${ENDPOINT}"
echo "  Requêtes : ${NB_REQUETES}, Concurrence : ${CONCURRENCE}"
echo ""

NB_APP=$(curl -s "${BASE_URL}/info" 2>/dev/null | python3 -c "import sys,json; print('ok')" 2>/dev/null && \
  for i in $(seq 1 10); do curl -sf "${BASE_URL}/info" 2>/dev/null; done | \
  python3 -c "
import sys, json
hotes = set()
for ligne in sys.stdin:
    ligne = ligne.strip()
    if ligne:
        try: hotes.add(json.loads(ligne)['hostname'])
        except: pass
print(len(hotes))
" || echo "?")

echo "Serveurs applicatifs détectés : ${NB_APP}"
echo ""

echo "--- Début du test de charge ---"
SORTIE=$(ab -n "$NB_REQUETES" -c "$CONCURRENCE" -q "${BASE_URL}${ENDPOINT}" 2>&1)

echo "$SORTIE" | grep -E "Requests per second|Time per request|Failed requests|Transfer rate"
echo "--- Fin du test de charge ---"
echo ""

ECHECS=$(echo "$SORTIE" | grep "Failed requests" | awk '{print $3}')
if [ "${ECHECS:-0}" -gt 0 ]; then
    echo "ATTENTION : ${ECHECS} requêtes ont échoué. Vérifier les logs HAProxy et applicatifs."
else
    echo "OK : aucune requête en échec."
fi

echo ""
echo "Pour comparer avec NB_APP=4 :"
echo "  1. Modifier NB_APP=4 dans .env"
echo "  2. vagrant up app3 app4"
echo "  3. vagrant provision lb1"
echo "  4. Relancer ce script"
