# RÉSULTATS-BF — Groupe 15

> Infrastructure reproductible Vagrant + VirtualBox pour consulter les résultats d'examens burkinabè.  
> Cinq machines virtuelles, une commande : `vagrant up`.

---

## Documentation — dans cet ordre

| # | Fichier | Quand le lire |
|---|---------|---------------|
| 1 | [docs/01-installation.md](docs/01-installation.md) | **Avant tout** — prérequis, installation, pièges courants |
| 2 | [docs/02-architecture.md](docs/02-architecture.md) | Pour comprendre comment le projet est construit |
| 3 | [docs/03-exploitation.md](docs/03-exploitation.md) | Pour opérer, diagnostiquer et gérer les incidents |
| 4 | [docs/04-journal-de-bord.md](docs/04-journal-de-bord.md) | Historique des décisions et problèmes rencontrés |

---

## Démarrage rapide

**Prérequis :** VirtualBox, Vagrant ≥ 2.4, Git. Voir [docs/01-installation.md](docs/01-installation.md) si c'est votre première fois.

```powershell
git clone <url-du-depot>
cd <dossier-du-depot>
Copy-Item .env.exemple .env
# Ouvrir .env et remplacer le mot de passe par défaut
vagrant validate
vagrant up
```

Le premier démarrage télécharge Ubuntu (~1 Go) et configure les 5 machines. Compter 15 à 30 minutes.

---

## Architecture du réseau

| Machine | Rôle | IP | RAM |
|---------|------|----|-----|
| `lb1` | HAProxy — répartiteur | 192.168.62.11 | 512 Mo |
| `app1` | Serveur applicatif | 192.168.62.21 | 512 Mo |
| `app2` | Serveur applicatif | 192.168.62.22 | 512 Mo |
| `bdd1` | PostgreSQL primaire | 192.168.62.31 | 768 Mo |
| `bdd2` | PostgreSQL standby | 192.168.62.32 | 768 Mo |

Réseau groupe 15 : `GROUPE_RESEAU=7` → `192.168.62.0/24`  
Seul `lb1` est accessible depuis l'hôte, sur le port `8080`.

---

### 1. Interface Web (Frontend Haute Disponibilité)
Dès que la commande `vagrant up` se termine avec succès, ouvrez immédiatement votre navigateur sur :  
👉 **[http://localhost:8080/](http://localhost:8080/)** *(ou [http://127.0.0.1:8080/](http://127.0.0.1:8080/))*

**Pourquoi ce choix ?**
Conformément à l'exigence **R8 (Cloisonnement réseau)**, aucune machine interne n'expose de port direct vers votre ordinateur hôte. Seul le répartiteur de charge `lb1` effectue le transfert de port `8080 (hôte) -> 80 (invité)`. Ce portail web :
- Interroge les nœuds applicatifs (`app1`, `app2`, ...) via HAProxy en Round-Robin.
- Affiche en direct le badge du serveur qui répond (`app1` ou `app2`) pour matérialiser visuellement la répartition.
- Permet de consulter en temps réel les 50 000 candidats burkinabè enregistrés en base.
- Offre une console de diagnostic en direct (`/sante`, `/info`, latence).

### 2. API REST (Backend)
Les endpoints de l'API backend (`app/app.py`) sont interrogeables via `curl` ou PowerShell :

```powershell
# Vérifier la répartition de charge (affiche app1 ou app2)
Invoke-RestMethod http://127.0.0.1:8080/info

# Vérifier la santé du service et la connexion PostgreSQL
Invoke-RestMethod http://127.0.0.1:8080/sante

# Consulter le résultat d'un candidat
Invoke-RestMethod "http://127.0.0.1:8080/resultat?matricule=BF-000001"
```

- `/` → Interface web si requête navigateur (`text/html`), métadonnées JSON si client HTTP.
- `/info` → nom du serveur qui a répondu (permet de constater la répartition en round-robin).
- `/sante` → `200 OK` si PostgreSQL répond, `503` sinon.
- `/resultat` → résultat JSON du candidat, `404` si inconnu, `400` si format invalide.

---

## Commandes courantes

```powershell
vagrant halt                   # Éteindre toutes les VM (sans les détruire)
vagrant up                     # Démarrer (ou recréer si nécessaire)
vagrant provision              # Rejouer les scripts de configuration
vagrant ssh bdd1               # Ouvrir un terminal sur bdd1
vagrant ssh lb1                # Ouvrir un terminal sur le répartiteur

# Bascule base de données (scénario V4)
vagrant ssh bdd2 -c "sudo /vagrant/scripts/bascule.sh"
```

---

## Livrables attendus par le professeur

Conformément au sujet du projet (Section 8 — Livrables) :

| Code | Livrable | Description |
|------|----------|-------------|
| **L1** | **Dépôt Git** | Le code complet (`Vagrantfile`, `scripts/`, `app/`, `config/`, `tests/`, `README.md`, `.env.exemple`). |
| **L2** | **Dossier d’architecture** | Document PDF (10 à 15 pages) : justification des choix, schémas, procédures et tableaux de résultats des scénarios V1 à V6. |
| **L3** | **Journal de bord** | Document de 1 à 2 pages ([docs/04-journal-de-bord.md](docs/04-journal-de-bord.md)) : répartition des rôles, décisions et difficultés résolues. |
| **L4** | **Démonstration** | Épreuve en direct (20 min) : reconstruction à partir de zéro (`vagrant destroy -f` puis `vagrant up`) et exécution de trois scénarios tirés au sort. |

---

## Dossier `tests/` — Scénarios de validation officiels

Le dossier `tests/` contient l'automatisation des scénarios d'évaluation demandés au chapitre 6 du sujet. Ces scripts permettent de produire les mesures pour le dossier d'architecture (**L2**) et de réussir la démonstration (**L4**).

| Fichier | Scénario évalué | Ce qu'il fait et mesure |
|---------|-----------------|-------------------------|
| `tests/test_app.py` | **Hors-VM** | Tests unitaires Python de l'API (`/sante`, `/info`, `/resultat`). Exécutable sur l'hôte sans démarrer de VM. |
| `tests/scenario_v1_repartition.sh` | **Scénario V1** | 20 appels consécutifs à `/info`. Calcule la distribution des requêtes et vérifie que l'écart entre serveurs est `< 20 %`. |
| `tests/scenario_v2_panne_app.sh` | **Scénario V2** | Simule la panne d'un serveur applicatif (`vagrant halt app1`) sous charge. Mesure le temps d'éviction par HAProxy (doit être `< 5 s`). |
| `tests/scenario_v3_charge.sh` | **Scénario V3** | Test de montée en charge avec Apache Bench (`ab -n 2000 -c 50`). Compare le débit (req/s) entre `NB_APP=2` et `NB_APP=4`. |
| `tests/scenario_v4_bascule_bdd.sh` | **Scénario V4** | Coupe le primaire `bdd1`, déclenche la promotion de `bdd2` via `scripts/bascule.sh` et chronomètre le temps de reprise du service. |
| `tests/scenario_v5_reconstruction.sh` | **Scénario V5 / R1** | Exécute `vagrant destroy -f` puis `vagrant up` et chronomètre la reconstruction intégrale sans intervention humaine. |
| `tests/scenario_v6_panne_lb.sh` | **Scénario V6 (Ext. E1)** | Coupe `lb1` et chronomètre la reprise automatique du trafic sur `lb2` via VRRP en moins de 5 secondes. |
| `tests/scenario_e4_deploiement.sh` | **Extension E4** | Exécute un test de charge continu pendant un déploiement sans coupure serveur par serveur (0 requête perdue). |

### Exécution des tests — PowerShell natif (recommandé sur Windows)

**Les scripts bash tournent à l'intérieur des VM Linux via `vagrant ssh`.  
Aucun WSL, aucun Git Bash requis.**

```powershell
# Menu interactif
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1

# Test rapide : /info, /sante et /resultat
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario Info

# V1 — Répartition de charge (round-robin app1 / app2)
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V1

# V2 — Panne applicative (crash app1, reprise sur app2 en < 5s)
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V2

# V3 — Test de charge Apache Bench (via lb1)
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V3

# V4 — Bascule base de données bdd1 → bdd2
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V4

# V6 — Panne répartiteur lb1, reprise par lb2 (Extension E1)
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V6

# E4 — Déploiement sans coupure (rolling update)
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario E4
```

> **Alternative (si Git Bash est disponible) :** `bash tests/scenario_v1_repartition.sh`, etc.

---

## Configuration `.env`

```env
GROUPE_EQUIPE=15       # Numéro d'équipe (ne pas modifier)
GROUPE_RESEAU=7        # Réseau : 15 mod 8 = 7 → 192.168.62.0/24
NB_APP=2               # Nombre de serveurs applicatifs (1 à 10)

POSTGRES_USER=resultats
POSTGRES_DB=resultats
POSTGRES_PASSWORD=     # À remplir — ne jamais committer un vrai mot de passe
```

`.env` est ignoré par Git (listé dans `.gitignore`). Ne le commitez jamais.

---

## Précautions

- `vagrant destroy -f` supprime les disques de toutes les VM. Irréversible. Consulter l'équipe avant.
- Ne jamais interrompre `vagrant up` avec Ctrl+C une fois qu'une VM est en cours de création — voir [docs/01-installation.md](docs/01-installation.md) si ça arrive malgré tout.
- Les données PostgreSQL vivent dans les VM, pas dans `/vagrant`. Elles disparaissent avec `destroy`.
