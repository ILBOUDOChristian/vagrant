#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Couleurs ANSI sobres
COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;32m"
COLOR_WARN="\033[0;33m"
COLOR_ERROR="\033[0;31m"

log_info()  { echo -e "${COLOR_INFO}INFO:${COLOR_RESET} $*"; }
log_warn()  { echo -e "${COLOR_WARN}WARNING:${COLOR_RESET} $*" >&2; }
log_error() { echo -e "${COLOR_ERROR}ERROR:${COLOR_RESET} $*" >&2; }

APP_SRC="/vagrant/app/app.py"
APP_DST="/opt/resultats-bf/app.py"
FRONTEND_DIR="/vagrant/frontend"
FRONTEND_DST_DIR="/opt/resultats-bf"
BDD_HOSTS="$(python3 - <<'PY'
import pathlib, re
text = pathlib.Path("/vagrant/config/noeuds.yml").read_text(encoding="utf-8")
current = {}
hosts = []
for raw in text.splitlines():
    m = re.match(r"^\s*-?\s*(nom|ip|role):\s*(.+)\s*$", raw)
    if not m:
        continue
    current[m.group(1)] = m.group(2).strip().strip("\"'")
    if m.group(1) == "role":
        if current.get("role") in ("bdd", "replique"):
            hosts.append(current["nom"])
        current = {}
if not hosts:
    raise SystemExit("aucun nœud de base dans config/noeuds.yml")
print(",".join(hosts))
PY
)"

if [ ! -f "$APP_SRC" ]; then
  echo "Application manquante : $APP_SRC" >&2
  exit 1
fi

apt-get install -y --no-install-recommends python3 postgresql-client
install -d -m 0755 /opt/resultats-bf
install -m 0644 "$APP_SRC" "$APP_DST"

# Copier les fichiers statiques du frontend
for f in index.html style.css app.js; do
  if [ -f "${FRONTEND_DIR}/${f}" ]; then
    install -m 0644 "${FRONTEND_DIR}/${f}" "${FRONTEND_DST_DIR}/${f}"
    log_info "Fichier statique copié : ${f}"
  else
    log_warn "Fichier statique manquant : ${FRONTEND_DIR}/${f}"
  fi
done

export BDD_HOSTS
umask 077
python3 - <<'PY' >/etc/default/resultats-bf
import os

for name in ("APP_HOST", "APP_PORT", "BDD_HOSTS", "BDD_PORT", "GROUPE_EQUIPE", "POSTGRES_USER", "POSTGRES_DB", "POSTGRES_PASSWORD", "URL_API_BASE"):
    value = os.environ.get(name, "")
    if name in ("APP_HOST", "APP_PORT", "BDD_PORT", "POSTGRES_USER", "POSTGRES_DB", "POSTGRES_PASSWORD") and not value:
        raise SystemExit(f"Erreur de configuration : {name} manquant dans l'environnement de provisionnement.")
    if "\n" in value or "\r" in value:
        raise SystemExit(f"Valeur de configuration invalide : {name}")
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    print(f'{name}="{escaped}"')
PY
chmod 0600 /etc/default/resultats-bf

cat >/etc/systemd/system/resultats-bf.service <<'UNIT'
[Unit]
Description=Application RESULTATS-BF
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/default/resultats-bf
ExecStart=/usr/bin/python3 /opt/resultats-bf/app.py
Restart=always
RestartSec=2
User=vagrant

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable resultats-bf
systemctl restart resultats-bf
systemctl is-active --quiet resultats-bf
log_info "L'application RESULTATS-BF est démarrée sur $(hostname) (port 8000)."
log_info "Sonde locale : http://127.0.0.1:8000/sante"
log_info "Accessible depuis l'hôte via le répartiteur : http://127.0.0.1:8080/"
