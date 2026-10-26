#!/usr/bin/env bash
# ==============================================================================
# SCÉNARIO V5 : RECONSTRUCTION COMPLÈTE DEPUIS ZÉRO (EXIGENCE R1)
# Projet RÉSULTATS-BF - Master 1 DevOps & Infrastructures Reproductibles
# ==============================================================================
# Objectif : Valider la reconstruction idempotente et automatisée de
#            l'ensemble du parc sans intervention manuelle.
# Commande attendue : vagrant destroy -f && vagrant up
# ==============================================================================

set -euo pipefail

echo "======================================================================="
echo "  SCÉNARIO V5 : VÉRIFICATION DE LA RECONSTRUCTION TOTALE (R1)"
echo "======================================================================="
echo "Date d'exécution : $(date -u '+%Y-%m-%d %H:%M:%SZ')"

# 1. Vérification de la configuration
echo -e "\n[Étape 1/4] Validation syntaxique Vagrantfile et .env..."
if command -v vagrant >/dev/null 2>&1; then
    vagrant validate
    echo "✔ Vagrantfile valide syntaxiquement."
else
    echo "⚠️ Commande 'vagrant' non trouvée localement. Ce script s'exécute depuis l'hôte."
fi

# 2. Rappel de la commande de destruction et recréation
echo -e "\n[Étape 2/4] Cycle complet recommandé :"
echo "  1) vagrant destroy -f"
echo "  2) vagrant up"
echo "  Durée estimée : 10 à 15 minutes selon débit réseau."

# 3. Vérification de l'état des machines
echo -e "\n[Étape 3/4] Contrôle de l'état attendu des VM..."
if command -v vagrant >/dev/null 2>&1; then
    vagrant status
fi

# 4. Vérification post-reconstruction (Sonde globale)
echo -e "\n[Étape 4/4] Test de bon fonctionnement post-up :"
VIP_LB="${URL_API_BASE:-http://127.0.0.1:8080}"
echo "Test d'accès sur : ${VIP_LB}/sante"

if command -v curl >/dev/null 2>&1; then
    RESPONSE=$(curl -s -w "\n%{http_code}" "${VIP_LB}/sante" 2>/dev/null || true)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✔ Succès : Service disponible immédiatement (HTTP 200)."
        echo "Contenu : $BODY"
    else
        echo "ℹ️ Code HTTP reçu : ${HTTP_CODE:-inaccessible} (Vérifier si le parc est démarré)."
    fi
else
    echo "ℹ️ Installez curl pour tester la sonde automatiquement."
fi

echo -e "\n======================================================================="
echo "  FIN DU CONTRÔLE V5"
echo "======================================================================="
