"""Module de service des fichiers statiques du portail RÉSULTATS-BF.

Gère l'envoi de index.html, style.css et app.js avec substitution
du placeholder {{URL_API_BASE}} dans le HTML.
"""
import os
import pathlib

URL_API_BASE = os.environ.get("URL_API_BASE", "")

STATIC_DIR = pathlib.Path(__file__).parent  # /opt/resultats-bf/

STATIC_FILES = {
    "/":           ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css":  ("style.css",  "text/css; charset=utf-8"),
    "/app.js":     ("app.js",     "application/javascript; charset=utf-8"),
}


def serve(handler, path: str) -> bool:
    """Tente de servir `path` comme fichier statique.

    Retourne True si la route est reconnue (et traitée),
    False si ce n'est pas une route statique (laisser l'API gérer).
    """
    if path not in STATIC_FILES:
        return False

    filename, content_type = STATIC_FILES[path]
    filepath = STATIC_DIR / filename

    if not filepath.exists():
        body = b'{"erreur":"fichier statique manquant"}'
        _send(handler, 404, "application/json; charset=utf-8", body)
        return True

    body = filepath.read_bytes()
    if filename.endswith(".html") and URL_API_BASE:
        body = body.replace(b"{{URL_API_BASE}}", URL_API_BASE.encode())

    _send(handler, 200, content_type, body)
    return True


def _send(handler, status: int, content_type: str, body: bytes) -> None:
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)
