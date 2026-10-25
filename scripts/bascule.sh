#!/bin/bash
set -euo pipefail

if [ "$(hostname)" != "bdd2" ]; then
  echo "ERROR: La bascule doit être exécutée sur bdd2." >&2
  exit 1
fi

if [ ! -f /var/lib/postgresql/.resultats-bf-replique ]; then
  echo "ERROR: bdd2 n'a pas été initialisée et vérifiée comme réplique." >&2
  exit 1
fi

if ! systemctl is-active --quiet postgresql; then
  echo "ERROR: PostgreSQL n'est pas actif sur bdd2." >&2
  exit 1
fi

if ! EN_RECUPERATION="$(sudo -u postgres psql -tAqc "SELECT pg_is_in_recovery()")"; then
  echo "ERROR: Impossible de vérifier l'état de PostgreSQL sur bdd2." >&2
  exit 1
fi

if [ "$EN_RECUPERATION" != "t" ]; then
  echo "INFO: bdd2 est déjà un serveur primaire ; aucune promotion n'est nécessaire."
  exit 0
fi

echo "INFO: Promotion de bdd2 en serveur primaire..."
DEBUT_MS=$(date +%s%3N)
if ! pg_ctlcluster 16 main promote; then
  echo "ERROR: La commande de promotion pg_ctlcluster a échoué." >&2
  exit 1
fi

for _ in $(seq 1 30); do
  if EN_RECUPERATION="$(sudo -u postgres psql -tAqc "SELECT pg_is_in_recovery()" 2>/dev/null)" &&
    [ "$EN_RECUPERATION" = "f" ]; then
    FIN_MS=$(date +%s%3N)
    DUREE_MS=$((FIN_MS - DEBUT_MS))
    DUREE_SEC=$(awk -v ms="$DUREE_MS" 'BEGIN { printf "%.3f", ms / 1000 }')
    echo "INFO: bdd2 est opérationnelle comme serveur primaire (durée de la promotion : ${DUREE_SEC}s)."
    exit 0
  fi
  sleep 1
done

FIN_MS=$(date +%s%3N)
DUREE_MS=$((FIN_MS - DEBUT_MS))
DUREE_SEC=$(awk -v ms="$DUREE_MS" 'BEGIN { printf "%.3f", ms / 1000 }')
echo "ERROR: La promotion de bdd2 n'a pas été confirmée après ${DUREE_SEC}s." >&2
exit 1
