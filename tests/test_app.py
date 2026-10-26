import json
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys
from threading import Thread
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app"))
import app


class ApplicationHttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def get_json(self, path):
        try:
            with urlopen(self.base_url + path, timeout=2) as response:
                return response.status, json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            return error.code, json.loads(error.read().decode("utf-8"))

    def test_info_returns_server_identity(self):
        status, payload = self.get_json("/info")
        self.assertEqual(status, 200)
        self.assertEqual(payload["statut"], "actif")
        self.assertEqual(payload["hostname"], payload["serveur"])

    def test_health_reports_database_outage(self):
        with patch.object(app, "check_db_health", return_value=(False, False)):
            status, payload = self.get_json("/sante")
        self.assertEqual(status, 503)
        self.assertEqual(payload, {"statut": "base_indisponible"})

    def test_health_reports_database_standby(self):
        with patch.object(app, "check_db_health", return_value=(True, True)):
            status, payload = self.get_json("/sante")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"statut": "ok", "mode": "standby"})

    def test_health_reports_database_primaire(self):
        with patch.object(app, "check_db_health", return_value=(True, False)):
            status, payload = self.get_json("/sante")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"statut": "ok", "mode": "primaire"})

    def test_result_endpoint_rejects_invalid_matricule(self):
        with patch.object(app, "fetch_candidate") as query:
            status, payload = self.get_json("/resultat?matricule=invalid")
        self.assertEqual(status, 400)
        self.assertEqual(payload, {"erreur": "matricule invalide"})
        query.assert_not_called()

    def test_result_endpoint_returns_candidate(self):
        candidate = {
            "matricule": "BF-000001",
            "nom": "OUEDRAOGO Wendyam",
            "serie": "A",
            "moyenne": 12.5,
            "admis": True,
        }
        with patch.object(app, "fetch_candidate", return_value=(candidate, None)):
            status, payload = self.get_json("/resultat?matricule=BF-000001")
        self.assertEqual(status, 200)
        self.assertEqual(payload, candidate)

    def test_sql_injection_attempt_is_rejected_by_pattern(self):
        injection = "BF-000001' OR '1'='1"
        status, payload = self.get_json(f"/resultat?matricule={injection}")
        self.assertEqual(status, 400)
        self.assertEqual(payload, {"erreur": "matricule invalide"})


if __name__ == "__main__":
    unittest.main()
