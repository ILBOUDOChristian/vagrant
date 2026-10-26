#!/usr/bin/env python3
"""API HTTP RESULTATS-BF : /info, /sante, /resultat?matricule=...
   + service des fichiers statiques du frontend (/, /style.css, /app.js)
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, logging, mimetypes, os, pathlib, re, socket, subprocess
from urllib.parse import parse_qs, urlparse

HOST        = os.environ.get("APP_HOST", "0.0.0.0")
PORT        = int(os.environ.get("APP_PORT", "8000"))
BDD_HOSTS   = [h.strip() for h in os.environ.get("BDD_HOSTS", "").split(",") if h.strip()]
BDD_PORT    = os.environ.get("BDD_PORT", "5432")
DB_NAME     = os.environ.get("POSTGRES_DB", "resultats_bf")
DB_USER     = os.environ.get("POSTGRES_USER", "resultats_user")
DB_PASSWORD = os.environ.get("POSTGRES_PASSWORD", "")
URL_API_BASE = os.environ.get("URL_API_BASE", "")

PAT_MATRICULE = re.compile(r"^BF-\d{6}$")

STATIC_DIR = pathlib.Path(__file__).parent          # /opt/resultats-bf/
STATIC_FILES = {
    "/":          ("index.html", "text/html; charset=utf-8"),
    "/index.html":("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css",  "text/css; charset=utf-8"),
    "/app.js":    ("app.js",     "application/javascript; charset=utf-8"),
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger("resultats-bf")


def query_db(sql_cmd, timeout=3):
    env = os.environ.copy()
    env["PGPASSWORD"] = DB_PASSWORD
    env["PGCONNECT_TIMEOUT"] = "1"
    for host in BDD_HOSTS:
        try:
            cmd = ["psql", "-X", "-w", "-v", "ON_ERROR_STOP=1",
                   "-h", host, "-p", str(BDD_PORT),
                   "-U", DB_USER, "-d", DB_NAME, "-tAq", "-c", sql_cmd]
            res = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
            if res.returncode == 0:
                return res.stdout.strip(), None
        except Exception as err:
            LOGGER.warning("Erreur connexion hôte %s: %s", host, err)
    return None, "db_unavailable"



def check_db_health():
    out, err = query_db("SELECT pg_is_in_recovery();", timeout=2)
    return (True, out == "t") if out is not None else (False, False)


def fetch_candidate(matricule):
    clean_mat = matricule.replace("'", "''")
    q = (f"SELECT row_to_json(r) FROM "
         f"(SELECT matricule, nom, serie, moyenne, admis "
         f"FROM resultats WHERE matricule = '{clean_mat}') r;")
    out, err = query_db(q, timeout=3)
    if err:
        return None, "db_unavailable"
    return (json.loads(out), None) if out else (None, "not_found")


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def serve_static(self, filename, content_type):
        """Sert un fichier statique depuis STATIC_DIR avec substitution de {{URL_API_BASE}}."""
        filepath = STATIC_DIR / filename
        if not filepath.exists():
            self.send_json(404, {"erreur": f"fichier statique manquant : {filename}"})
            return
        body = filepath.read_bytes()
        # Substitution du placeholder dans le HTML uniquement
        if filename.endswith(".html") and URL_API_BASE:
            body = body.replace(b"{{URL_API_BASE}}", URL_API_BASE.encode("utf-8"))
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        hostname = socket.gethostname()

        # Fichiers statiques du frontend
        if url.path in STATIC_FILES:
            filename, content_type = STATIC_FILES[url.path]
            self.serve_static(filename, content_type)
            return

        # API JSON
        if url.path == "/info":
            self.send_json(200, {"hostname": hostname, "serveur": hostname, "statut": "actif"})
        elif url.path == "/sante":
            ok, standby = check_db_health()
            if ok:
                self.send_json(200, {"statut": "ok", "mode": "standby" if standby else "primaire"})
            else:
                self.send_json(503, {"statut": "base_indisponible"})
        elif url.path == "/resultat":
            params = parse_qs(url.query, max_num_fields=5)
            mat = params.get("matricule", [None])[0]
            if not mat or not PAT_MATRICULE.match(mat):
                self.send_json(400, {"erreur": "matricule invalide"})
                return
            cand, err = fetch_candidate(mat)
            if cand:
                self.send_json(200, cand)
            elif err == "not_found":
                self.send_json(404, {"erreur": "candidat non trouvé", "matricule": mat})
            else:
                self.send_json(503, {"erreur": "base de données indisponible"})
        else:
            self.send_json(404, {"erreur": "ressource inconnue"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    LOGGER.info("RÉSULTATS-BF démarré sur %s:%s — statiques dans %s", HOST, PORT, STATIC_DIR)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
