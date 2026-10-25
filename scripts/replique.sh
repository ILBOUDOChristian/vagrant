#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [ "$(hostname)" != "bdd2" ]; then
  echo "Ce script doit être exécuté sur bdd2." >&2
  exit 1
fi

VERSION_POSTGRES=16
PG_DATA="/var/lib/postgresql/${VERSION_POSTGRES}/main"
MARQUEUR="/var/lib/postgresql/.resultats-bf-replique"
BACKUP_DIR="${PG_DATA}.avant-replication"
PASSWORD="${POSTGRES_PASSWORD:-a-changer}"
PASSFILE="/var/lib/postgresql/.pgpass-resultats-bf"

echo "Installation de PostgreSQL sur bdd2..."
apt-get install -y --no-install-recommends postgresql postgresql-contrib
systemctl enable postgresql

CIDR="${RESEAU:-192.168.62}.0/24"
PG_HBA="$(sudo -u postgres psql -tAqc "SHOW hba_file" 2>/dev/null || echo "/etc/postgresql/16/main/pg_hba.conf")"
sudo -u postgres psql -v ON_ERROR_STOP=1 \
  -c "ALTER SYSTEM SET listen_addresses = '*';" 2>/dev/null || true

sed -i '/^# BEGIN RESULTATS-BF$/,/^# END RESULTATS-BF$/d' "$PG_HBA"
cat >> "$PG_HBA" <<EOF
# BEGIN RESULTATS-BF
host all all $CIDR scram-sha-256
host replication replicator $CIDR scram-sha-256
# END RESULTATS-BF
EOF

if [ -f "$MARQUEUR" ]; then
  systemctl start postgresql
  if ETAT="$(sudo -u postgres psql -tAqc \
    "SELECT CASE WHEN NOT pg_is_in_recovery() THEN 'primary' WHEN EXISTS (SELECT FROM pg_stat_wal_receiver WHERE status = 'streaming') THEN 'streaming' ELSE 'standby_disconnected' END" 2>/dev/null)" &&
    [ "$ETAT" = "streaming" ]; then
    echo "La réplication de bdd2 est déjà opérationnelle."
    exit 0
  fi

  if [ "${ETAT:-}" = "primary" ]; then
    echo "bdd2 a été promue en serveur primaire ; ses données ont été conservées."
    exit 0
  fi

  echo "bdd2 a déjà été initialisée comme réplique, mais le flux n'est pas actif. Aucune donnée n'a été remplacée." >&2
  exit 1
fi

systemctl start postgresql
PG_DATA_ACTUEL="$(sudo -u postgres psql -tAqc "SHOW data_directory")"
if [ "$PG_DATA_ACTUEL" != "$PG_DATA" ]; then
  echo "Répertoire PostgreSQL inattendu : $PG_DATA_ACTUEL" >&2
  exit 1
fi

BASES_EXISTANTES="$(sudo -u postgres psql -d postgres -tAqc \
  "SELECT count(*) FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> 'postgres'")"
if [ "$BASES_EXISTANTES" != "0" ]; then
  echo "bdd2 contient déjà une base applicative. Aucune donnée n'a été remplacée." >&2
  exit 1
fi
if [ -e "$BACKUP_DIR" ]; then
  echo "Une sauvegarde préalable existe déjà : $BACKUP_DIR. Vérifiez-la avant de poursuivre." >&2
  exit 1
fi

echo "Attente de PostgreSQL sur bdd1..."
PRET=false
for _ in $(seq 1 30); do
  if pg_isready -h bdd1 -p 5432 -t 2 -d postgres >/dev/null 2>&1; then
    PRET=true
    break
  fi
  sleep 2
done
if [ "$PRET" != "true" ]; then
  echo "PostgreSQL sur bdd1 n'est pas joignable après 60 secondes." >&2
  exit 1
fi

BASEBACKUP_DIR="$(mktemp -d "${PG_DATA}.basebackup.XXXXXX")"
chown postgres:postgres "$BASEBACKUP_DIR"
chmod 0700 "$BASEBACKUP_DIR"
trap 'if [ -d "$BASEBACKUP_DIR" ]; then rm -rf -- "$BASEBACKUP_DIR"; fi' EXIT

echo "Copie initiale des données depuis bdd1..."
systemctl stop postgresql
export POSTGRES_PASSWORD="$PASSWORD"
install -o postgres -g postgres -m 0600 /dev/null "$PASSFILE"
python3 - <<'PY' > "$PASSFILE"
import os

password = os.environ["POSTGRES_PASSWORD"].replace("\\", "\\\\").replace(":", "\\:")
print(f"bdd1:5432:replication:replicator:{password}")
PY
chown postgres:postgres "$PASSFILE"
chmod 0600 "$PASSFILE"
sudo -u postgres pg_basebackup \
  --dbname="host=bdd1 port=5432 user=replicator dbname=replication passfile=$PASSFILE" \
  -D "$BASEBACKUP_DIR" \
  -Fp \
  -Xs \
  -R \
  --checkpoint=fast

mv "$PG_DATA" "$BACKUP_DIR"
if ! mv "$BASEBACKUP_DIR" "$PG_DATA"; then
  mv "$BACKUP_DIR" "$PG_DATA"
  systemctl start postgresql
  echo "Impossible d'installer la copie de réplication ; l'ancien cluster a été restauré." >&2
  exit 1
fi
chown -R postgres:postgres "$PG_DATA"
chmod 0700 "$PG_DATA"

systemctl start postgresql
REPLICATION_ACTIVE=false
for _ in $(seq 1 30); do
  if ETAT="$(sudo -u postgres psql -tAqc \
    "SELECT CASE WHEN NOT pg_is_in_recovery() THEN 'primary' WHEN EXISTS (SELECT FROM pg_stat_wal_receiver WHERE status = 'streaming') THEN 'streaming' ELSE 'standby_disconnected' END" 2>/dev/null)" &&
    [ "$ETAT" = "streaming" ]; then
    REPLICATION_ACTIVE=true
    break
  fi
  sleep 2
done

if [ "$REPLICATION_ACTIVE" != "true" ]; then
  echo "Le flux de réplication n'est pas actif. Le cluster initial est conservé dans $BACKUP_DIR." >&2
  exit 1
fi

printf '%s\n' "RESULTATS-BF réplique initialisée" > "$MARQUEUR"
chmod 0600 "$MARQUEUR"
rm -rf -- "$BACKUP_DIR"
echo "La réplication entre bdd1 et bdd2 est opérationnelle."
