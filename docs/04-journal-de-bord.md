# Journal de bord — RÉSULTATS-BF, Groupe 15

Ce journal documente les décisions prises, les problèmes rencontrés et comment ils ont été résolus. Les mesures de performance seront complétées après exécution réelle des scénarios.

---

## Rappel des exigences obligatoires du sujet



| N° | Exigence |
|----|----------|
| R1 | Reconstruction intégrale : `vagrant destroy -f` puis `vagrant up` reconstruit tout, sans commande manuelle |
| R2 | Idempotence : `vagrant provision` rejoué deux fois ne modifie rien et n'échoue pas |
| R3 | Le nombre de serveurs applicatifs est un paramètre — passer de 2 à 4 ne change qu'une valeur dans `.env` |
| R4 | Le répartiteur n'envoie du trafic qu'aux serveurs qui répondent sur `/sante`, et écarte un serveur défaillant en moins de 5 secondes |
| R5 | `bdd2` est une réplique en flux de `bdd1` — une écriture sur `bdd1` est visible sur `bdd2` |
| R6 | Une procédure de bascule est écrite, exécutable et chronométrée |
| R7 | Aucun secret en clair dans le dépôt — les mots de passe passent par des variables d'environnement |
| R8 | Tout le trafic interne passe par le réseau privé — seul le répartiteur expose un port vers l'hôte |

**Point interdit explicitement dans le sujet :**
Les adresses des serveurs applicatifs ne doivent pas être écrites en dur dans la configuration du répartiteur. HAProxy doit être configuré à partir de la même source de vérité que le Vagrantfile. C'est le coeur de R3 : sans cela, le paramètre `NB_APP` ne sert à rien.

---

## Session 1 — Montage du socle complet

### Contexte

Le Vagrantfile initial couvrait le jalon 1 : un serveur de base de données (`bdd1`), un serveur applicatif (`app1`) et un répartiteur (`lb1`). L'objectif de cette session était d'atteindre le socle complet du sujet : ajout de `bdd2` en réplication, passage à `NB_APP=2` par défaut, implémentation de la procédure de bascule et couverture des exigences R1 à R8.

---

### Problème 1 — `vagrant up` échoue au démarrage de `bdd1`

**Ce que le projet demandait :**
Lancer les cinq machines avec `vagrant up`. VirtualBox doit créer les disques des VM et leur attribuer les noms définis dans le Vagrantfile (`resultats-bf-bdd1`, etc.).

**Problème rencontré :**
```
VBoxManage.exe: error: Could not rename the directory
'...\ubuntu-24.04-amd64_1792375697089_11162'
to '...\resultats-bf-bdd1' (VERR_ALREADY_EXISTS)
```

**Pourquoi l'erreur ne guide pas :**
L'erreur vient de VirtualBox lui-même, pas de Vagrant. Vagrant demande à VirtualBox de créer la VM, VirtualBox répond avec un code d'erreur bas niveau, et Vagrant s'arrête sans pouvoir donner plus de contexte parce que le problème vient du système externe. Le message indique juste qu'un dossier existe déjà, mais ne dit pas combien ni lesquels.

**Diagnostic effectué :**
Après inspection du dossier des VM et de la liste VirtualBox, il y avait en réalité cinq résidus laissés par trois tentatives précédentes interrompues :

| Dossier | Origine |
|---------|---------|
| `resultats-bf-bdd1` | Tentative 1 |
| `resultats-bf-bdd2` | Tentative 1 |
| `resultats-bf-app1` | Tentative 1 |
| `ubuntu-24.04-amd64_..._50648` | Tentative 2, import interrompu |
| `ubuntu-24.04-amd64_..._11162` | Tentative 3, import interrompu |

Plus cinq verrous Vagrant dans `.vagrant/machines/` (un par machine).

**Résolution :**

Désinscription de la VM temporaire encore enregistrée dans VirtualBox :
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" unregistervm "ubuntu-24.04-amd64_1792375697089_11162"
```

Suppression des cinq dossiers résiduels dans le répertoire des VM :
```powershell
Remove-Item -Recurse -Force "D:\Dev\VMs\RESULTATS-BF\resultats-bf-bdd1"
Remove-Item -Recurse -Force "D:\Dev\VMs\RESULTATS-BF\resultats-bf-bdd2"
Remove-Item -Recurse -Force "D:\Dev\VMs\RESULTATS-BF\resultats-bf-app1"
Remove-Item -Recurse -Force "D:\Dev\VMs\RESULTATS-BF\ubuntu-24.04-amd64_1792375203874_50648"
Remove-Item -Recurse -Force "D:\Dev\VMs\RESULTATS-BF\ubuntu-24.04-amd64_1792375697089_11162"
```

Suppression des verrous Vagrant :
```powershell
Remove-Item -Recurse -Force ".vagrant\machines\bdd1"
Remove-Item -Recurse -Force ".vagrant\machines\bdd2"
Remove-Item -Recurse -Force ".vagrant\machines\app1"
Remove-Item -Recurse -Force ".vagrant\machines\app2"
Remove-Item -Recurse -Force ".vagrant\machines\lb1"
```

Après ces opérations, le dossier `RESULTATS-BF` était vide et aucune VM du projet n'était enregistrée dans VirtualBox. `vagrant up` a pu s'exécuter.

**Ce qu'on retient :**
Ne pas interrompre `vagrant up` avec Ctrl+C une fois que VirtualBox a commencé à créer une VM. À chaque interruption, VirtualBox laisse un nouveau dossier résiduel. La procédure de nettoyage est documentée dans [docs/01-installation.md](01-installation.md).

---

### Problème 2 — `vagrant destroy` bloqué par un processus en attente

**Ce que le projet demandait :**
Nettoyer les VM orphelines avec `vagrant destroy -f` pour repartir d'un état connu, conformément à l'exigence R1.

**Problème rencontré :**
```
An action 'destroy' was attempted on the machine 'bdd1',
but another process is already executing an action on the machine.
```

L'interruption précédente avait laissé un processus Vagrant actif en arrière-plan. Vagrant pose un verrou sur chaque machine pendant toute opération, et ce verrou n'est libéré que si le processus se termine normalement.

**Résolution :**
Identifier le processus Vagrant bloqué dans le gestionnaire des tâches Windows et le terminer manuellement, puis relancer `vagrant destroy -f`.

---

### Problème 3 — `vagrant validate` produisait des modifications Git non voulues

**Ce que le projet demandait :**
Utiliser `vagrant validate` pour vérifier la syntaxe du Vagrantfile. Cette commande est une simple lecture et ne doit rien modifier.

**Problème rencontré :**
Chaque appel à `vagrant validate` ou `vagrant status` modifiait le fichier `config/noeuds.yml`, ce qui apparaissait dans `git status` comme une modification. Plusieurs membres commençant à travailler en même temps auraient produit des commits sans contenu réel.

**Cause :**
Le Vagrantfile recalculait et réécrivait `config/noeuds.yml` à chaque évaluation Ruby, y compris pour les commandes qui ne font que consulter l'état du projet.

**Solution appliquée dans le Vagrantfile :**
```ruby
nouveau_yaml = inventaire.to_yaml
if !File.exist?(noeuds_path) || File.read(noeuds_path) != nouveau_yaml
  File.write(noeuds_path, nouveau_yaml)
end
```
Le fichier n'est réécrit que si son contenu a réellement changé.

---

### Décisions techniques et justifications

**Réplication PostgreSQL via `pg_basebackup -R` :**
Le sujet exige une réplication en flux (R5). L'option `-R` génère automatiquement les fichiers de configuration nécessaires (`standby.signal`, connexion au primaire). Une configuration manuelle de ces fichiers aurait été plus risquée et dépendante de la version exacte de PostgreSQL présente dans la box.

**Fallback automatique de l'application vers `bdd2` :**
Après la bascule (R6), l'application doit continuer à fonctionner sans qu'on intervienne sur les serveurs applicatifs. L'application liste ses hôtes dans l'ordre (`bdd1,bdd2`) et tente chaque hôte. Après la promotion de `bdd2`, les requêtes basculent sans redémarrage de service.

**Configuration HAProxy générée depuis `config/noeuds.yml` :**
Le sujet interdit explicitement d'écrire les adresses des serveurs en dur dans HAProxy. Le script `lb.sh` lit `config/noeuds.yml` et génère la section `backend` dynamiquement. Changer `NB_APP=4` dans `.env` suffit pour que HAProxy intègre les nouveaux serveurs au prochain `vagrant provision lb1` (R3).

**Accès PostgreSQL via `psql` en sous-processus :**
Le driver Python `psycopg2` nécessite `pip`, absent par défaut sur Ubuntu 24.04. Les VM sont provisionnées uniquement par les scripts Bash du projet, sans installation de gestionnaire de paquets Python. Les requêtes sont paramétrées via `-v matricule=... / :'matricule'` pour éviter les injections SQL.

---

## État du projet

### Code

| Fichier | État |
|---------|------|
| `Vagrantfile` | Complet, validé (`vagrant validate` : OK) |
| `scripts/commun.sh` | Complet, idempotent |
| `scripts/bdd.sh` | Complet, 50 000 lignes, réplication configurée |
| `scripts/replique.sh` | Complet, protection contre l'écrasement accidentel |
| `scripts/app.sh` | Complet, hôtes BDD lus depuis `noeuds.yml` |
| `scripts/lb.sh` | Complet, sonde `/sante` active, éviction sous 5 s |
| `scripts/bascule.sh` | Complet, chronométré, préconditions vérifiées |
| `app/app.py` | Complet, fallback automatique `bdd1` vers `bdd2` |
| `tests/test_app.py` | Complet, exécutable sans VM |
| `tests/scenario_v*.sh` | Écrits, non encore exécutés sur VM réelle |

### Mesures à compléter

- [ ] Temps de reconstruction complète (`vagrant destroy -f` puis `vagrant up`).
- [ ] Durée de promotion PostgreSQL (scénario V4).
- [ ] Débit Apache Bench avec NB_APP=2 puis NB_APP=4 (scénario V3).
- [ ] Temps d'éviction HAProxy (scénario V2).

---

## Répartition officielle des rôles (Groupe 15 — Master 1)

Conformément à la composition officielle de l'équipe (Groupe 15) et aux 4 rôles prescrits par le Dr SOMDA :

| Rôle académique | Périmètre technique | Membre assigné (Filière) | Rotation obligatoire (commit croisé) |
| :--- | :--- | :--- | :--- |
| **Architecte réseau & répartition** | Plan d'adressage, Vagrantfile, HAProxy, Keepalived/VRRP (E1) | **Palingwendé Aude Stanislas** (SI) | Tests et validation scénario V1 & V6 |
| **Ingénieur données** | PostgreSQL, réplication streaming, bascule bdd2, E3/jeu 50k | **Songr La Panga Christian** (SI) | Revue sécurité Vagrantfile & script commun |
| **Ingénieur applicatif** | API Python (<100 lignes), absence d'état, rolling update (E4) | **Yesso Yasmina** (SIE) | Tests unitaires Python et vérification BDD |
| **Ingénieur essais & observabilité**| Automatisation tests V1 à V6, dossier d'architecture, mesures | **Julius Wendkuuni** (SI) | Script de déploiement sans coupure & sonde |

> **Règle académique respectée :** Chaque membre assure la pleine maîtrise de son périmètre principal tout en ayant contribué concrètement sur les autres briques du cluster pour la soutenance orale.
