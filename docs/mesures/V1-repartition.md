# Mesures V1 — Répartition de charge (Round-Robin)
> Scénario V1 — Exigence R3 / R4 — Date : _____

## Commande exécutée
```powershell
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V1
```

## Résultats

| Serveur | Requêtes reçues | Pourcentage | Verdict |
|---|---|---|---|
| app1 | 10 / 20 | 50% | ✅ Conforme |
| app2 | 10 / 20 | 50% | ✅ Conforme |
| Erreurs | 0 | 0% | ✅ Parfait (0 erreur) |

**Écart de répartition :** 0% (seuil exigé : < 20 %)  
**Verdict global :** ☑ CONFORME  ☐ NON CONFORME

## Sortie brute de la commande
```text
-------------------------------------------------------
  V1 -- Repartition de charge HAProxy
-------------------------------------------------------
        Envoi de 20 requetes sur /info via HAProxy...
          Req 1 -> app1
          Req 2 -> app2
          Req 3 -> app1
          Req 4 -> app2
          Req 5 -> app1
          Req 6 -> app2
          Req 7 -> app1
          Req 8 -> app2
          Req 9 -> app1
          Req 10 -> app2
          Req 11 -> app1
          Req 12 -> app2
          Req 13 -> app1
          Req 14 -> app2
          Req 15 -> app1
          Req 16 -> app2
          Req 17 -> app1
          Req 18 -> app2
          Req 19 -> app1
          Req 20 -> app2

        app1=10 | app2=10 | erreurs=0
[OK]    Les deux serveurs ont recu du trafic (Ecart: 0 requetes = 0% <= 20%).
```
