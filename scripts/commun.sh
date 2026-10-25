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

log_info "Mise à jour de l'index des paquets..."
apt-get update -qq
log_info "Installation des outils communs..."
apt-get install -y --no-install-recommends python3 ca-certificates

NOEUDS="/vagrant/config/noeuds.yml"
if [ ! -f "$NOEUDS" ]; then
  log_error "Inventaire manquant : $NOEUDS"
  exit 1
fi

python3 - "$NOEUDS" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
nodes = []
current = {}
for raw in text.splitlines():
    match = re.match(r"^\s*-?\s*(nom|ip|mem|role):\s*(.+)\s*$", raw)
    if not match:
        continue
    current[match.group(1)] = match.group(2).strip().strip("\"'")
    if match.group(1) == "role" and "nom" in current and "ip" in current:
        nodes.append(current)
        current = {}

if not nodes:
    raise SystemExit("aucun nœud valide dans config/noeuds.yml")
if len({node["nom"] for node in nodes}) != len(nodes):
    raise SystemExit("noms de nœuds dupliqués dans config/noeuds.yml")
if len({node["ip"] for node in nodes}) != len(nodes):
    raise SystemExit("adresses IP dupliquées dans config/noeuds.yml")

block = ["# BEGIN RESULTATS-BF"]
for node in nodes:
    block.append(f"{node['ip']} {node['nom']}")
block.append("# END RESULTATS-BF")
payload = "\n".join(block) + "\n"

hosts = pathlib.Path("/etc/hosts")
content = hosts.read_text(encoding="utf-8")
pattern = re.compile(r"# BEGIN RESULTATS-BF.*?# END RESULTATS-BF\n?", re.S)
if pattern.search(content):
    content = pattern.sub(payload, content)
else:
    content = content.rstrip() + "\n" + payload
if content != hosts.read_text(encoding="utf-8"):
    hosts.write_text(content, encoding="utf-8")
PY

log_info "Configuration des clés SSH internes pour l'orchestration..."
SSH_DIR="/home/vagrant/.ssh"
mkdir -p "$SSH_DIR"
SHARED_KEY_DIR="/vagrant/config/ssh"
mkdir -p "$SHARED_KEY_DIR"

if [ ! -f "$SHARED_KEY_DIR/id_ed25519" ]; then
  ssh-keygen -t ed25519 -N "" -f "$SHARED_KEY_DIR/id_ed25519" -C "resultats-bf-cluster"
  chmod 600 "$SHARED_KEY_DIR/id_ed25519"
  chmod 644 "$SHARED_KEY_DIR/id_ed25519.pub"
fi

cp "$SHARED_KEY_DIR/id_ed25519" "$SSH_DIR/id_ed25519"
cp "$SHARED_KEY_DIR/id_ed25519.pub" "$SSH_DIR/id_ed25519.pub"
cat "$SHARED_KEY_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"
sort -u "$SSH_DIR/authorized_keys" -o "$SSH_DIR/authorized_keys"
chown -R vagrant:vagrant "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/id_ed25519" "$SSH_DIR/authorized_keys"
chmod 644 "$SSH_DIR/id_ed25519.pub"

log_info "La résolution des noms des machines est configurée."

