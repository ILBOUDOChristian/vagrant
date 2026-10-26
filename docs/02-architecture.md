# Architecture de RÉSULTATS-BF — Groupe 15

## 1. Contexte et contraintes

RÉSULTATS-BF est une plateforme de consultation des résultats d'examens construite dans le cadre du Master 1 DevOps. Les contraintes imposées par le sujet sont :

- Vagrant + VirtualBox 
- Ubuntu 24.04 avec une version de box épinglée (`202404.26.0`).
- Réseau privé VirtualBox dans la plage `192.168.56.0/21`.
- Maximum 8 sous-réseaux de groupe : `G ∈ {1…8}`, formule `192.168.(55+G).0/24`.
- Notre groupe : **GROUPE_EQUIPE=15**, **GROUPE_RESEAU=7** (15 mod 8 = 7), réseau `192.168.62.0/24`.
- Mémoire totale contenue dans 3 Go (contrainte matérielle machine hôte).
- Reconstruction intégrale depuis `vagrant destroy -f` puis `vagrant up` sans intervention manuelle.

## 2. Architecture générale

### 2.1 Machines virtuelles

| Machine | Rôle | Adresse IP | RAM | Port hôte |
|---------|------|-----------|-----|-----------|
| `lb1`   | Répartiteur HAProxy | 192.168.62.11 | 512 Mo | 8080 → 80 |
| `app1`  | Serveur applicatif  | 192.168.62.21 | 512 Mo | — |
| `app2`  | Serveur applicatif  | 192.168.62.22 | 512 Mo | — |
| `bdd1`  | PostgreSQL primaire | 192.168.62.31 | 768 Mo | — |
| `bdd2`  | PostgreSQL standby  | 192.168.62.32 | 768 Mo | — |

Mémoire totale configurée : **3 072 Mo**. Le paramètre `NB_APP` dans `.env` permet d'ajouter des serveurs applicatifs sans modifier le Vagrantfile.

### 2.2 Diagramme des flux

```
Navigateur / curl (hôte)
        |
        | http://localhost:8080
        v
   [ lb1 : HAProxy ]  →  GET /sante (sonde active, toutes les 2s)
        |
    round-robin
        |
   +----+----+
   |         |
[ app1 ]  [ app2 ]
 :8000      :8000
   |         |
   | psql via réseau privé
   |
   |  bdd1 joignable ?  →  oui → requête SQL
   |  sinon             →  bdd2 (fallback automatique)
   |
[ bdd1 ] ─── WAL streaming ──→ [ bdd2 ]
primaire (lecture+écriture)      standby (lecture seule)
```

Seul `lb1` est joignable depuis la machine hôte. Toutes les communications internes passent par `192.168.62.0/24`.

## 3. Description de chaque composant

### 3.1 Vagrantfile — Chef d'orchestre

**Ce qu'il fait :**
- Lit les variables d'environnement depuis `.env` (GROUPE_RESEAU, NB_APP, mots de passe PostgreSQL).
- Calcule dynamiquement le sous-réseau : `RESEAU = "192.168.#{55 + GROUPE_RESEAU}"`.
- Définit la liste unique des nœuds (`NOEUDS`) qui est la seule source de vérité pour les adresses IP et les rôles.
- Écrit `config/noeuds.yml` **uniquement si le contenu a changé**, évitant les modifications inutiles lors d'un `vagrant validate` ou `vagrant status`.
- Passe les variables d'environnement (`PROVISION_ENV`) aux scripts de provisionnement.

**Pourquoi ce choix :**
La logique est centralisée dans le Vagrantfile plutôt que dupliquée dans plusieurs fichiers. Changer `NB_APP=4` dans `.env` adapte automatiquement les VM créées, l'inventaire YAML et la configuration HAProxy sans aucune autre modification.

### 3.2 `scripts/commun.sh` — Socle réseau

**Ce qu'il fait :**
- Installe les dépendances minimales (`python3`, `ca-certificates`).
- Parse `config/noeuds.yml` et injecte un bloc nommé dans `/etc/hosts` pour que chaque VM puisse joindre les autres par nom (`ping bdd1`, `curl app1:8000`).
- Protège contre les doublons : si `/etc/hosts` contient déjà le bloc, il est remplacé en place (idempotent).
- Valide la cohérence de l'inventaire (noms et IPs uniques).

**Ce qu'il ne fait pas :**
N'installe pas de logiciel métier (PostgreSQL, HAProxy). Chaque rôle a son propre script.

### 3.3 `scripts/bdd.sh` — PostgreSQL primaire (`bdd1`)

**Ce qu'il fait :**
1. Installe PostgreSQL 16.
2. Configure `listen_addresses = '*'` et `wal_level = 'replica'` via `ALTER SYSTEM`.
3. Met à jour `pg_hba.conf` avec un bloc délimité (idempotent) autorisant :
   - Connexions applicatives : `host all all 192.168.62.0/24 scram-sha-256`
   - Connexions de réplication : `host replication replicator 192.168.62.0/24 scram-sha-256`
4. Crée les rôles PostgreSQL (`resultats` et `replicator`) via des requêtes paramétrées (`\gexec`) sans jamais interpoler le mot de passe dans du SQL littéral.
5. Crée la table `resultats` et insère **50 000 lignes** avec `generate_series`. L'insertion est idempotente grâce à `ON CONFLICT (matricule) DO NOTHING`.
6. Applique des droits stricts : l'utilisateur applicatif a uniquement `SELECT` sur la table `resultats`.

**Décision de sécurité :**
Le mot de passe est transmis via la variable d'environnement `POSTGRES_PASSWORD` et lu par psql avec `\getenv`. Il n'apparaît jamais dans les arguments de ligne de commande ou dans les logs.

### 3.4 `scripts/replique.sh` — PostgreSQL standby (`bdd2`)

**Ce qu'il fait :**
1. Vérifie que le script tourne bien sur `bdd2` (garde-fou explicite).
2. Si le marqueur `/var/lib/postgresql/.resultats-bf-replique` existe, vérifie l'état de la réplication et sort sans modifier les données.
3. Vérifie que `bdd2` ne contient pas encore de base applicative (protection contre l'écrasement accidentel).
4. Attend que `bdd1` soit prête (boucle sur `pg_isready`, timeout 60 s avec sortie explicite).
5. Clone `bdd1` via `pg_basebackup -R`, qui génère automatiquement `standby.signal` et la configuration de connexion au primaire.
6. Démarre PostgreSQL en mode standby : il applique les WAL de `bdd1` en continu.

**Pourquoi `pg_basebackup -R` et pas une configuration manuelle :**
L'option `-R` génère `postgresql.auto.conf` et `standby.signal` de façon cohérente avec la version de PostgreSQL installée, sans risque d'erreur de syntaxe manuelle.

### 3.5 `scripts/bascule.sh` — Procédure de failover

**Ce qu'il fait :**
1. Vérifie les préconditions : exécuté sur `bdd2`, PostgreSQL actif, marqueur de réplique présent.
2. Vérifie que `bdd2` est bien en mode standby (`pg_is_in_recovery() = true`). Si elle est déjà primaire, sort proprement.
3. Exécute `pg_ctlcluster 16 main promote`.
4. Boucle sur `pg_is_in_recovery()` jusqu'à confirmation de la promotion (timeout 30 s).
5. Affiche la durée exacte en secondes (ex. : `INFO: bdd2 est opérationnelle comme serveur primaire (durée : 1.243s)`).
6. Retourne `exit 1` avec un message explicite si la promotion n'est pas confirmée.

**Après la bascule :**
Les serveurs applicatifs (`app1`, `app2`) tentent `bdd1` puis `bdd2`. Dès que `bdd1` est éteinte, ils basculent automatiquement sur `bdd2` qui est désormais primaire.

### 3.6 `scripts/app.sh` — Déploiement applicatif

**Ce qu'il fait :**
1. Installe `postgresql-client` (nécessaire pour que `app.py` invoque `psql`).
2. Copie `app.py` vers `/opt/resultats-bf/app.py`.
3. Écrit `/etc/default/resultats-bf` avec les variables d'environnement (port, hôtes BDD, credentials).
4. Crée et active le service systemd `resultats-bf.service` (`Restart=always`, redémarre en 2 s en cas de crash).

**Pourquoi systemd et non un processus manuel :**
Systemd gère le redémarrage automatique, le logging dans journald et le démarrage au boot, sans dépendance à une session SSH ouverte.

### 3.7 `scripts/lb.sh` — Configuration HAProxy

**Ce qu'il fait :**
1. Installe HAProxy.
2. Parse `config/noeuds.yml` et extrait tous les nœuds de rôle `app`.
3. Génère `/etc/haproxy/haproxy.cfg` avec :
   - `option httpchk GET /sante` : sonde de santé active.
   - `check inter 2s fall 2 rise 2` : un serveur est écarté après 2 échecs (4 s), remis en circulation après 2 succès.
4. Valide la configuration générée avec `haproxy -c` avant de recharger.

**Exigence R4 :**
La détection d'une panne applicative prend au maximum `2s × 2 = 4 secondes < 5 secondes`.

### 3.8 `app/app.py` — Service HTTP

**Ce qu'il fait :**

| Endpoint | Méthode | Comportement |
|----------|---------|--------------|
| `/info` | GET | Renvoie `{"hostname", "serveur", "statut"}`. Permet d'observer la répartition HAProxy. |
| `/sante` | GET | Exécute `SELECT 1;` sur la première BDD joignable. HTTP 200 si OK, 503 si indisponible. |
| `/resultat` | GET | Paramètre `matricule=BF-XXXXXX`. Valide le format, exécute `SELECT ... FROM resultats WHERE matricule = :'matricule'`. HTTP 200 / 400 / 404 / 503. |

**Multi-host fallback :**
La variable `BDD_HOSTS` contient `bdd1,bdd2`. L'application essaie chaque hôte dans l'ordre. Lors d'une bascule, les requêtes basculent automatiquement sur `bdd2` sans redémarrage du service.

**Choix technique — `subprocess psql` vs driver Python :**
Le projet utilise `psql` via `subprocess` pour éviter toute dépendance externe (`psycopg2` n'est pas inclus dans les paquets Ubuntu sans `pip`). Le sujet n'autorise pas d'installation de gestionnaire de paquets Python sur les VM. Les requêtes sont entièrement paramétrées via `-v matricule=...` et `:'matricule'` pour éviter les injections SQL.

**Limite connue :**
Chaque requête HTTP crée un processus `psql`. Sous charge intensive (> 100 req/s), les performances sont inférieures à un driver avec pool de connexions. Pour le volume du sujet (démonstration de 50 000 lignes et test de charge académique), cette limite est acceptable.

## 4. Source de vérité unique

`config/noeuds.yml` est généré par le Vagrantfile et consommé par :
- `commun.sh` → `/etc/hosts` sur chaque VM.
- `app.sh` → `BDD_HOST` dans la configuration systemd.
- `lb.sh` → liste des serveurs `backend` dans HAProxy.

Aucune adresse IP n'est codée en dur dans les scripts. Changer une adresse dans `Vagrantfile` propage automatiquement la modification à tous les composants au prochain `vagrant provision`.

## 5. Gestion des secrets

- Les mots de passe sont définis dans `.env` (non versionné, listé dans `.gitignore`).
- `.env.exemple` est versionné avec des valeurs de démonstration explicitement marquées.
- Les scripts reçoivent les secrets via des variables d'environnement Vagrant (`PROVISION_ENV`).
- PostgreSQL reçoit les mots de passe via `\getenv` (jamais en ligne de commande ou SQL interpolé).
- L'application reçoit les credentials via `/etc/default/resultats-bf` (fichier readable par root uniquement).

## 6. Reproductibilité et idempotence

Chaque script est conçu pour être exécuté plusieurs fois sans produire d'erreur :

| Script | Mécanisme d'idempotence |
|--------|------------------------|
| `commun.sh` | Replace le bloc `/etc/hosts` en place |
| `bdd.sh` | `ON CONFLICT DO NOTHING`, `IF NOT EXISTS`, `ALTER SYSTEM` |
| `replique.sh` | Marqueur fichier, vérification de l'état PostgreSQL |
| `app.sh` | `install -m`, `systemctl enable --now` |
| `lb.sh` | Régénère et recharge HAProxy |

## 7. Stratégie de tests

### Tests unitaires (hors VM)
Fichier : `tests/test_app.py`
Exécution : `python -m unittest discover -s tests` depuis la racine du projet.
Couverture : validation des formats, codes HTTP attendus, comportement sans BDD.

### Tests d'intégration et scénarios (VM nécessaires)

| Scénario | Commande | Résultat attendu |
|----------|----------|-----------------|
| V1 — Répartition | `tests/scenario_v1_repartition.sh` | app1 et app2 apparaissent sur /info |
| V2 — Panne app | `tests/scenario_v2_panne_app.sh` | Éviction en < 5s, service maintenu |
| V3 — Charge | `tests/scenario_v3_charge.sh` | Mesure ab avec NB_APP=2 vs NB_APP=4 |
| V4 — Bascule BDD | `tests/scenario_v4_bascule_bdd.sh` | Promotion bdd2, /sante revient à 200 |

## 8. Extensions implémentées (E1 et E4)

### Extension E1 — Répartiteur redondant (Keepalived + VRRP)
- **Objectif :** Éliminer le point de défaillance unique sur `lb1`.
- **Mécanisme :** Deux répartiteurs (`lb1` MASTER priorité 101, `lb2` BACKUP priorité 100) partagent l'adresse IP virtuelle `192.168.62.5`. En cas de panne de `lb1`, Keepalived bascule la VIP en moins de 2 secondes sans interruption pour les utilisateurs.
- **Validation :** Scénario V6 (`tests/scenario_v6_panne_lb.sh`).

### Extension E4 — Déploiement sans coupure (Rolling Update)
- **Objectif :** Mettre à jour l'application serveur par serveur pendant la charge sans aucune erreur HTTP 5xx.
- **Mécanisme :** Le script `scripts/deploiement_sans_coupure.sh` dialogue avec le socket administratif HAProxy `/run/haproxy/admin.sock`. Pour chaque serveur :
  1. Passage en mode `drain` (fin des requêtes en cours).
  2. Passage en mode `maint`.
  3. Déploiement de la mise à jour et redémarrage du service.
  4. Validation stricte de la sonde `/sante` (doit retourner HTTP 200).
  5. Réintégration en mode `ready`.
- **Validation :** Scénario E4 (`tests/scenario_e4_deploiement.sh`).

## 9. Limites techniques et perspectives industrielles

1. **Bascule manuelle / semi-automatisée de la base (R6) :** Le basculement de `bdd2` est piloté par un script dédié (`bascule.sh`) plutôt qu'un quorum automatique (comme Patroni). Ce choix est conforme aux exigences du sujet et évite le risque de *split-brain* involontaire sur réseau instable.
2. **Re-synchronisation inverse :** Après promotion de `bdd2`, l'ancien primaire `bdd1` doit être réinitialisé via `pg_basebackup` avant d'être réintégré comme réplique.
3. **Accès PostgreSQL via `psql` :** Permet une portabilité absolue sans dépendance `pip`/`psycopg2` sur les nœuds applicatifs. Pour une montée en charge de production à grande échelle, un pooler tel que PgBouncer et un driver binaire seraient privilégiés.
