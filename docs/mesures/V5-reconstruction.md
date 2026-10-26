# Mesures V5 — Reconstruction intégrale automatisée
> Scénario V5 — Exigence R1 / R2 (Reproductibilité) — Date : 26 Octobre 2026

## Commande exécutée
```powershell
Measure-Command { vagrant destroy -f ; vagrant up }
```

## Résultats mesurés

| Phase | Durée observée | Statut |
|---|---|---|
| Destruction complète (`vagrant destroy -f`) | ~35 s | ✅ 5 VM supprimées sans résidu |
| Importation Box Ubuntu 24.04 (Noble) | ~40 s | ✅ 5 machines provisionnées |
| Provisionnement PostgreSQL + Réplication (`bdd1`, `bdd2`) | ~1 min 20 s | ✅ 50 000 lignes chargées, réplication active |
| Provisionnement Applicatifs Python (`app1`, `app2`) | ~1 min 15 s | ✅ Services systemd actifs |
| Provisionnement HAProxy + Keepalived (`lb1`) | ~55 s | ✅ Port 80 / 8080 opérationnel |
| **Durée totale mesurée** | **~4 min 45 s** | ✅ Cluster 100% opérationnel zéro intervention |

**Verdict global :** ☑ CONFORME (reconstruction 100% en code, idempotente et sans action manuelle).

## Validation finale automatique
```text
========================================================================
  INFRASTRUCTURE RESULTATS-BF DEPLOYEE AVEC SUCCES !
  Portail Web disponible sur : http://127.0.0.1:8080/
  Sonde de sante active     : http://127.0.0.1:8080/sante
  Repartition de charge     : http://127.0.0.1:8080/info
  Recherche de resultat     : http://127.0.0.1:8080/resultat?matricule=BF-000006
========================================================================
```
