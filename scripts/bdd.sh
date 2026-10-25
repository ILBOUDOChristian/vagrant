#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

USER_NAME="${POSTGRES_USER:-resultats_user}"
DB_NAME="${POSTGRES_DB:-resultats_bf}"
PASSWORD="${POSTGRES_PASSWORD:-a-changer}"
CIDR="${RESEAU:-192.168.62}.0/24"

if [[ ! "$CIDR" =~ ^192\.168\.(5[6-9]|6[0-3])\.0/24$ ]]; then
  echo "Réseau privé invalide : $CIDR" >&2
  exit 1
fi

echo "Installation de PostgreSQL..."
apt-get install -y --no-install-recommends postgresql postgresql-contrib
systemctl enable --now postgresql

PG_HBA="$(sudo -u postgres psql -tAqc "SHOW hba_file")"

sudo -u postgres psql -v ON_ERROR_STOP=1 \
  -c "ALTER SYSTEM SET listen_addresses = '*';" \
  -c "ALTER SYSTEM SET wal_level = 'replica';" \
  -c "ALTER SYSTEM SET max_wal_senders = '10';"

sed -i '/^# BEGIN RESULTATS-BF$/,/^# END RESULTATS-BF$/d' "$PG_HBA"
sed -i '/^# RESULTATS-BF jalon1$/,+1d' "$PG_HBA"
cat >> "$PG_HBA" <<EOF
# BEGIN RESULTATS-BF
host all all $CIDR scram-sha-256
host replication replicator $CIDR scram-sha-256
# END RESULTATS-BF
EOF

echo "Application de la configuration PostgreSQL..."
systemctl restart postgresql

export POSTGRES_PASSWORD="$PASSWORD"
sudo -u postgres --preserve-env=POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 \
  -v app_user="$USER_NAME" \
  -v app_db="$DB_NAME" <<'SQL'
\getenv app_password POSTGRES_PASSWORD
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec

SELECT format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'app_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') \gexec
SELECT format('ALTER ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'app_password')
WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') \gexec

SELECT format('CREATE DATABASE %I OWNER postgres', :'app_db')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'app_db') \gexec
SELECT format('ALTER DATABASE %I OWNER TO postgres', :'app_db') \gexec
SELECT format('REVOKE ALL PRIVILEGES ON DATABASE %I FROM %I', :'app_db', :'app_user') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'app_db', :'app_user') \gexec
\connect :"app_db"

CREATE TABLE IF NOT EXISTS resultats (
    matricule VARCHAR(20) PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    serie VARCHAR(10) NOT NULL,
    moyenne NUMERIC(4, 2) NOT NULL,
    admis BOOLEAN NOT NULL
);

WITH candidats AS (
    SELECT
        i,
        (ARRAY['A', 'C', 'D', 'G'])[((i - 1) % 4 + 1)::integer] AS serie,
        (((i * 37) % 1201)::numeric / 100 + 8)::numeric(4, 2) AS moyenne,
        (ARRAY[
            'OUEDRAOGO', 'SAWADOGO', 'KABORE', 'TRAORE', 'SANOGO',
            'BAMBARA', 'ZONGO', 'COMPAORE', 'ILBOUDO', 'DIALLO',
            'KONE', 'OUATTARA', 'GANAME', 'YAMEOGO', 'SOME',
            'NABALOUM', 'TIENDREBEOGO', 'BADINI', 'KERE', 'ROAMBA'
        ])[((i - 1) % 20 + 1)::integer] AS nom_famille,
        (ARRAY[
            'Ibrahim', 'Fatoumata', 'Moussa', 'Awa', 'Abdoulaye',
            'Aminata', 'Cheick', 'Salimata', 'Souleymane', 'Nafissatou',
            'Wendyam', 'Barkwende', 'Pingdwende', 'Kiswendsida', 'Rayangnewende',
            'Alassane', 'Mariam', 'Adama', 'Kadidiatou', 'Oumarou'
        ])[(((i * 7) - 1) % 20 + 1)::integer] AS prenom
    FROM generate_series(1, 50000) AS i
)
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT
    'BF-' || LPAD(i::text, 6, '0'),
    nom_famille || ' ' || prenom,
    serie,
    moyenne,
    moyenne >= 10.00
FROM candidats
ON CONFLICT (matricule) DO UPDATE
SET nom = EXCLUDED.nom;

ALTER TABLE resultats OWNER TO postgres;
REVOKE ALL PRIVILEGES ON TABLE resultats FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE resultats FROM :"app_user";
GRANT USAGE ON SCHEMA public TO :"app_user";
GRANT SELECT ON TABLE resultats TO :"app_user";
SQL

COUNT_RESULTATS="$(sudo -u postgres psql -d "$DB_NAME" -tAqc "SELECT count(*) FROM resultats")"
if [ "$COUNT_RESULTATS" != "50000" ]; then
  echo "La base contient $COUNT_RESULTATS résultats au lieu de 50000." >&2
  exit 1
fi

echo "PostgreSQL est configuré et les 50000 résultats sont disponibles."
