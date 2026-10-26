#!/usr/bin/env python3
"""API HTTP RÉSULTATS-BF — /info  /sante  /resultat?matricule=BF-XXXXXX"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import json, logging, os, re, socket, subprocess, static

HOST      = os.environ.get("APP_HOST", "0.0.0.0")
PORT      = int(os.environ.get("APP_PORT", "8000"))
BDD_HOSTS = [h.strip() for h in os.environ.get("BDD_HOSTS", "").split(",") if h.strip()]
BDD_PORT  = os.environ.get("BDD_PORT", "5432")
DB_NAME   = os.environ.get("POSTGRES_DB", "resultats_bf")
DB_USER   = os.environ.get("POSTGRES_USER", "resultats_user")
DB_PASS   = os.environ.get("POSTGRES_PASSWORD", "")
PAT       = re.compile(r"^BF-\d{6}$")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("resultats-bf")


def _query(sql, timeout=3):
    env = {**os.environ, "PGPASSWORD": DB_PASS, "PGCONNECT_TIMEOUT": "1"}
    for host in BDD_HOSTS:
        try:
            r = subprocess.run(
                ["psql", "-X", "-w", "-v", "ON_ERROR_STOP=1",
                 "-h", host, "-p", BDD_PORT, "-U", DB_USER, "-d", DB_NAME,
                 "-tAq", "-c", sql],
                capture_output=True, text=True, env=env, timeout=timeout,
            )
            if r.returncode == 0:
                return r.stdout.strip(), None
        except Exception as e:
            LOG.warning("Hôte %s inaccessible : %s", host, e)
    return None, "db_unavailable"


def _health():
    out, _ = _query("SELECT pg_is_in_recovery();", timeout=2)
    return (True, out == "t") if out is not None else (False, False)


def _resultat(matricule):
    m = matricule.replace("'", "''")
    sql = (f"SELECT row_to_json(r) FROM "
           f"(SELECT matricule, nom, serie, moyenne, admis "
           f"FROM resultats WHERE matricule = '{m}') r;")
    out, err = _query(sql)
    if err:
        return None, "db_unavailable"
    return (json.loads(out), None) if out else (None, "not_found")


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if static.serve(self, url.path):
            return
        if url.path == "/info":
            h = socket.gethostname()
            self._json(200, {"hostname": h, "serveur": h, "statut": "actif"})
        elif url.path == "/sante":
            ok, standby = _health()
            self._json(200 if ok else 503,
                       {"statut": "ok", "mode": "standby" if standby else "primaire"}
                       if ok else {"statut": "base_indisponible"})
        elif url.path == "/resultat":
            params = parse_qs(url.query, max_num_fields=5)
            mat = params.get("matricule", [None])[0]
            if not mat or not PAT.match(mat):
                self._json(400, {"erreur": "matricule invalide"})
                return
            cand, err = _resultat(mat)
            if cand:
                self._json(200, cand)
            elif err == "not_found":
                self._json(404, {"erreur": "candidat non trouvé", "matricule": mat})
            else:
                self._json(503, {"erreur": "base de données indisponible"})
        else:
            self._json(404, {"erreur": "ressource inconnue"})

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    LOG.info("RÉSULTATS-BF démarré %s:%s", HOST, PORT)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
