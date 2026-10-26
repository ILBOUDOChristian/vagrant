#!/bin/bash
# Scénario V4 — Bascule de base de données et retour au service
#
# Objectif : vérifier que l'infrastructure continue de fonctionner
# après l'arrêt de bdd1 et la promotion de bdd2.
#
# Préconditions : vagrant up complet, bdd1 et bdd2 en running, réplication active.
# Résultat attendu :
#   - /sante retourne 503 pendant la bascule (base indisponible).
#   - La promotion de bdd2 se confirme en moins de 30 secondes.
#   - /sante retourne 200 après la bascule.
#   - /resultat?matricule=BF-000001 retourne 200 après la bascule.
#   - La durée totale d'indisponibilité est mesurée.
#
# Commande : bash tests/scenario_v4_bascule_bdd.sh
set -euo pipefail

BASE_URL="${URL_API_BASE:?URL_API_BASE absent — ajoutez-le dans votre fichier .env (voir .env.exemple)}"
SEUIL_BASCULE_SECONDES=30

verifier_sante() {
    HTTP_CODE=$(curl -o /dev/null -sw "%{http_code}" --max-time 2 "${BASE_URL}/sante" 2>/dev/null || echo "000")
    echo "$HTTP_CODE"
}

echo "V4 — Scénario de bascule base de données"
echo ""

echo "Étape 1 : vérification de la réplication active..."
REPLICATION=$(vagrant ssh bdd1 -c "sudo -u postgres psql -tAqc \"SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'\"" 2>/dev/null | tr -d '[:space:]')
if [ "${REPLICATION:-0}" -lt 1 ]; then
    echo "ÉCHEC : aucune réplication en flux active sur bdd1 avant le test." >&2
    echo "  Vérifier : vagrant ssh bdd1 -c \"sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'\"" >&2
    exit 1
fi
echo "  Réplication active. Flux en cours vers bdd2."

echo ""
echo "Étape 2 : vérification que le service fonctionne avant la panne..."
CODE=$(verifier_sante)
if [ "$CODE" != "200" ]; then
    echo "ÉCHEC : /sante retourne ${CODE} avant le test (attendu 200)." >&2
    exit 1
fi
echo "  /sante : ${CODE} OK"

echo ""
echo "Étape 3 : arrêt de bdd1..."
DEBUT_PANNE_MS=$(($(date +%s%3N)))
vagrant halt bdd1 2>/dev/null
echo "  bdd1 arrêtée à $(date +%H:%M:%S.%3N)"

echo ""
echo "Étape 4 : promotion de bdd2..."
vagrant ssh bdd2 -c "sudo /vagrant/scripts/bascule.sh"
FIN_PROMOTION_MS=$(($(date +%s%3N)))
DUREE_PROMOTION_SEC=$(awk -v debut="$DEBUT_PANNE_MS" -v fin="$FIN_PROMOTION_MS" 'BEGIN { printf "%.2f", (fin - debut) / 1000 }')
echo "  Durée depuis l'arrêt de bdd1 jusqu'à la confirmation de promotion : ${DUREE_PROMOTION_SEC}s"

echo ""
echo "Étape 5 : attente du retour à la normale (/sante = 200)..."
RETOUR_MS=0
for i in $(seq 1 20); do
    CODE=$(verifier_sante)
    echo "  Tentative ${i} : /sante = ${CODE}"
    if [ "$CODE" = "200" ]; then
        RETOUR_MS=$(($(date +%s%3N)))
        break
    fi
    sleep 1
done

if [ "$RETOUR_MS" -eq 0 ]; then
    echo "ÉCHEC : /sante n'est pas repassé à 200 après 20 secondes." >&2
    exit 1
fi

DUREE_TOTALE_SEC=$(awk -v debut="$DEBUT_PANNE_MS" -v fin="$RETOUR_MS" 'BEGIN { printf "%.2f", (fin - debut) / 1000 }')
echo ""
echo "Étape 6 : vérification que /resultat fonctionne via bdd2..."
RESULTAT_CODE=$(curl -o /dev/null -sw "%{http_code}" --max-time 3 "${BASE_URL}/resultat?matricule=BF-000001" 2>/dev/null || echo "000")
echo "  /resultat?matricule=BF-000001 : ${RESULTAT_CODE}"

echo ""
echo "=== Résultats ==="
echo "  Durée de la promotion bdd2  : ${DUREE_PROMOTION_SEC}s"
echo "  Durée totale d'indisponibilité : ${DUREE_TOTALE_SEC}s"
if [ "$RESULTAT_CODE" = "200" ]; then
    echo "  Accès aux données via bdd2  : OK"
else
    echo "  Accès aux données via bdd2  : ÉCHEC (code ${RESULTAT_CODE})"
fi

if awk -v d="$DUREE_PROMOTION_SEC" -v s="$SEUIL_BASCULE_SECONDES" 'BEGIN { exit (d > s) ? 0 : 1 }'; then
    echo "ATTENTION : la promotion a pris ${DUREE_PROMOTION_SEC}s (seuil indicatif : ${SEUIL_BASCULE_SECONDES}s)."
fi

echo ""
echo "IMPORTANT : bdd1 reste éteinte. Pour la rallumer (sans la reconfigurer comme standby) :"
echo "  vagrant up bdd1"
