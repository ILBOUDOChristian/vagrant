# Mesures V2 — Panne d'un serveur applicatif
> Scénario V2 — Exigence R4 — Date : _____

## Commande exécutée
```powershell
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V2
```

## Résultats

| Métrique | Valeur mesurée | Seuil exigé | Verdict |
|---|---|---|---|
| Durée d'éviction HAProxy | 3 s | < 5 s | ☑ OK ☐ KO |
| Requêtes en erreur pendant éviction | 0 | 0 idéal | ☑ OK ☐ KO |
| Serveur actif après bascule | app2 | app2 | ☑ OK ☐ KO |
| Service redémarré sur app1 | ☑ Oui ☐ Non | Oui | ☑ OK ☐ KO |

**Verdict global :** ☑ CONFORME  ☐ NON CONFORME

## Sortie brute de la commande
```text
-------------------------------------------------------
  V2 -- Panne applicative (crash app1)
-------------------------------------------------------
        Arret de resultats-bf sur app1...
        Envoi continu de requetes (max 15s)...
[OK]    Trafic repris sur app2 en 3 s.
        Redemarrage de app1...
```
