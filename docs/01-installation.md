# Guide d'installation — RÉSULTATS-BF

Ce projet tourne entièrement dans des machines virtuelles gérées par Vagrant et VirtualBox. Votre poste de travail sert uniquement de support : vous n'installez pas l'application ni PostgreSQL dessus. Ce guide explique quoi installer sur votre machine, comment configurer les emplacements de stockage si votre disque système est limité, et les problèmes courants à éviter.

---

## 1. Prérequis et dépendances à installer

Pour exécuter ce projet, la machine hôte doit disposer uniquement de **trois dépendances logicielles fondamentales** (aucun framework, aucun serveur BDD ni langage n'est à installer sur l'hôte) :

### Dépendances logicielles obligatoires à installer sur l'hôte :
1. **Git for Windows** (pour cloner le dépôt et fournir un terminal Bash).
2. **Oracle VirtualBox** (version 7.0 ou 7.1/7.2 - l'hyperviseur qui fait tourner les VM).
3. **HashiCorp Vagrant ≥ 2.4** (l'outil d'automatisation qui pilote VirtualBox).

### Prérequis matériels et système :
- **Système d'exploitation :** Windows 10/11 64 bits (PowerShell 5.1 ou plus).
- **Virtualisation matérielle (VT-x / AMD-V) :** Doit être **activée dans le BIOS/UEFI** de votre ordinateur (obligatoire pour VirtualBox).
- **Mémoire RAM :** 8 Go au total sur le PC (le socle de 5 VM utilise **3 Go de RAM** au total, laissant 5 Go pour Windows).
- **Espace disque :** Minimum **10 à 15 Go d'espace libre** pour stocker l'image Ubuntu 24.04 et les disques virtuels des 5 machines.

> Si `vagrant up` échoue avec une erreur VT-x ou Hyper-V, vérifiez que la virtualisation est bien active dans votre gestionnaire des tâches (onglet Performance > Processeur > *Virtualisation : Activé*).

### Vérifier les dépendances installées :

```powershell
git --version                                            # Dépendance 1 : Git
& "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe" --version  # Dépendance 2 : VirtualBox
vagrant --version                                        # Dépendance 3 : Vagrant (doit être >= 2.4)
```

---

## 2. Installation des outils hôtes

### Git

```powershell
winget install Git.Git
# ou télécharger depuis https://git-scm.com/download/win
```

### Oracle VirtualBox

Télécharger depuis https://www.virtualbox.org/wiki/Downloads.

Le programme s'installe dans `C:\Program Files\Oracle\VirtualBox`. C'est normal : le programme lui-même est léger. Ce qui prend de la place, ce sont les **disques des VM**.

**Choisir où créer les nouvelles VM.** Si votre disque `C:` est limité, redirigez les VM vers un volume spacieux. Chaque membre choisit le chemin qui lui convient :

```powershell
# Remplacer D:\VirtualBox-VMs par le chemin de votre choix
& "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe" setproperty machinefolder "D:\VirtualBox-VMs"
& "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe" list systemproperties | Select-String "Default machine folder"
```

Ce réglage est **global sur votre poste**. Il ne touche pas aux VM déjà enregistrées.

### Vagrant ≥ 2.4

Télécharger le MSI depuis https://developer.hashicorp.com/vagrant/install.

L'installeur place le binaire `vagrant.exe` dans `C:\HashiCorp\Vagrant\bin` ou `C:\Program Files\HashiCorp\Vagrant\bin` selon la version. Vérifiez qu'il est bien dans le PATH :

```powershell
vagrant --version
```

Si la commande n'est pas trouvée, cherchez `vagrant.exe` sur votre disque et ajoutez son dossier au PATH utilisateur :

```powershell
# Adapter le chemin selon où l'installeur a placé vagrant.exe sur votre machine
[System.Environment]::SetEnvironmentVariable("Path",
    [System.Environment]::GetEnvironmentVariable("Path","User") + ";C:\HashiCorp\Vagrant\bin",
    "User")
# Ouvrir un nouveau terminal pour que le changement soit pris en compte
```

**Boxes volumineuses : choisir où les stocker.** Les boxes Vagrant (images Ubuntu, ≈ 1 Go) se téléchargent dans `%USERPROFILE%\.vagrant.d` par défaut. Si votre profil Windows est sur `C:` et que cet espace est limité, redirigez via `VAGRANT_HOME`. Chaque membre adapte à sa situation :

```powershell
# Remplacer D:\Vagrant-boxes par le chemin de votre choix
[System.Environment]::SetEnvironmentVariable("VAGRANT_HOME", "D:\Vagrant-boxes", "User")
$env:VAGRANT_HOME = "D:\Vagrant-boxes"
New-Item -ItemType Directory -Force -Path $env:VAGRANT_HOME | Out-Null
```

> Si vous ne définissez pas `VAGRANT_HOME`, Vagrant utilisera `C:\Users\<vous>\.vagrant.d`. C'est parfaitement correct si vous avez de la place.

Ouvrir un **nouveau** terminal PowerShell après avoir modifié des variables d'environnement.

---

## 3. Réseau du groupe

Le sujet autorise G ∈ {1…8} : sous-réseau `192.168.(55+G).0/24`, dans la plage VirtualBox `192.168.56.0/21`.

Notre équipe porte le numéro **15**. On n'utilise pas 15 dans la formule (ce serait `192.168.70.0/24`, refusé). On utilise `15 mod 8 = 7` :

| Variable | Valeur | Usage |
|----------|--------|-------|
| `GROUPE_EQUIPE` | 15 | Identifiant d'équipe |
| `GROUPE_RESEAU` | 7 | Calcul du réseau : `55 + 7 = 62` |
| Réseau | `192.168.62.0/24` | Plage des VM |

Ne modifiez pas `networks.conf` de VirtualBox.

---

## 4. Démarrage du projet

### Avant de taper la moindre commande

**VirtualBox doit être lancé.** Vagrant pilote VirtualBox en arrière-plan, mais si VirtualBox n'est pas démarré, les commandes échouent sans message clair. Ouvrez l'application VirtualBox (icône dans le menu Démarrer) et laissez-la ouverte pendant que vous travaillez.

**Le PATH doit contenir `vagrant`.** Si vous venez d'installer Vagrant ou d'ouvrir un nouveau terminal, vérifiez :

```powershell
vagrant --version
```

Si la commande n'est pas reconnue, rechargez le PATH sans fermer le terminal :

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
vagrant --version   # doit répondre maintenant
```

### Lancer le projet

```powershell
git clone <url-du-depot>
cd <dossier-du-depot>
Copy-Item .env.exemple .env
# Ouvrir .env et remplacer le mot de passe par défaut
vagrant validate
vagrant up
vagrant status
```

La box `bento/ubuntu-24.04` version `202404.26.0` est épinglée : tout le groupe télécharge la même image. Le premier `vagrant up` prend 15 à 30 minutes (téléchargement + provisionnement des 5 VM). Les suivants sont beaucoup plus rapides.

### Que fait exactement `vagrant up` et pourquoi est-ce long au premier lancement ?

#### 1. Pourquoi le premier lancement prend du temps
C'est tout à fait normal lors de la toute première création :
- **Téléchargement réseau :** Chaque VM met à jour son index de paquets Ubuntu (`apt-get update`) et télécharge ses outils officiels depuis Internet (`postgresql-16` sur `bdd1`/`bdd2`, `haproxy` sur `lb1`).
- **Disques virtuels :** VirtualBox doit allouer et initialiser 5 disques durs virtuels distincts (`.vdi`) sur votre machine hôte.
- **Population de la base :** `bdd1` insère les 50 000 lignes de données requises par le sujet, puis `bdd2` clone entièrement ces données via `pg_basebackup`.

> **Note :** Les lancements suivants (par exemple après un `vagrant halt` pour éteindre le PC) démarrent les machines en **quelques secondes**.

#### 2. Ordre d'appel des fichiers
Quand vous tapez `vagrant up` :
1. **`Vagrantfile`** : Chef d'orchestre. Il charge les variables `.env`, alloue la RAM (768 Mo / 512 Mo) et les IP privées (`192.168.62.x`), et génère automatiquement `config/noeuds.yml`.
2. **`config/noeuds.yml`** : Fichier d'inventaire dynamique partagé avec toutes les VM (source unique de vérité).
3. **Provisioning (Scripts Bash)** :
   - `scripts/commun.sh` s'exécute sur **toutes les VM** pour configurer la résolution `/etc/hosts`.
   - `scripts/bdd.sh` configure PostgreSQL et insère les 50 000 résultats sur `bdd1`.
   - `scripts/replique.sh` configure la réplication en flux sur `bdd2`.
   - `scripts/app.sh` installe l'API Python et le service systemd sur `app1` et `app2`.
   - `scripts/lb.sh` génère la configuration HAProxy dynamique avec la sonde `/sante` sur `lb1`.

#### 3. Comment déboguer en cas d'erreur ou d'interruption
Si une étape échoue ou semble bloquée :
1. **Repérer la machine en erreur :** Dans la console, chaque ligne de log commence par le nom de la machine (ex: `bdd1: ...` ou `lb1: ...`). Lisez toujours les dernières lignes affichées.
2. **Se connecter en SSH à la machine :**
   ```powershell
   vagrant ssh app1    # remplacer par bdd1, bdd2 ou lb1
   ```
3. **Inspecter les journaux de service :**
   ```bash
   # Logs de l'application Python :
   journalctl -u resultats-bf -n 50 --no-pager
   # Logs PostgreSQL :
   sudo journalctl -u postgresql -n 50 --no-pager
   # Logs HAProxy :
   sudo journalctl -u haproxy -n 50 --no-pager
   ```
4. **Rejouer uniquement le script qui a échoué (sans détruire les VM) :**
   Si la connexion a coupé pendant l'installation, vous n'avez pas besoin de tout détruire. Rejouez simplement le provisionnement de la machine concernée :
   ```powershell
   vagrant provision bdd1
   # ou
   vagrant provision app1
   ```

### Comprendre le dossier `.vagrant/` : peut-on le supprimer ?

Le dossier `.vagrant/` est créé automatiquement par Vagrant dès la première commande. Il fonctionne exactement comme un environnement virtuel Python (`.venv`) :

- **Ce qu'il contient :** De simples fichiers texte légers (quelques Ko) avec les identifiants uniques (UUID) des VM créées dans VirtualBox et les clés privées SSH temporaires.
- **Ce qu'il NE contient PAS :** Il ne contient pas les disques durs des machines (les fichiers `.vdi` de plusieurs Go qui sont stockés dans le dossier VirtualBox).
- **Dans Git :** Il est obligatoirement listé dans `.gitignore`. Chaque membre de l'équipe et chaque machine a son propre `.vagrant/` généré localement.

#### Quand et comment le supprimer sans risque ?

> [!WARNING]
> **Ne supprimez pas `.vagrant/` brutalement si des VM tournent encore dans VirtualBox !**
> Si vous supprimez `.vagrant/` alors que les VM existent, Vagrant perd leur trace. Les VM continueront de tourner ou d'occuper de la place sur votre disque en tant que "machines fantômes" orphelines.

1. **La manière propre (recommandée) :**
   ```powershell
   vagrant destroy -f
   ```
   Cette commande demande à VirtualBox de détruire proprement les disques et nettoie automatiquement `.vagrant/`.

2. **Si Vagrant est bloqué ou désynchronisé (nettoyage forcé) :**
   Si vous voulez supprimer manuellement le dossier `.vagrant/`, procédez toujours dans cet ordre :
   - Ouvrez l'interface graphique **VirtualBox**.
   - Supprimez manuellement les VM du projet si elles apparaissent (Clic droit > *Supprimer* > *Supprimer tous les fichiers*).
   - Supprimez le dossier `.vagrant/` dans le projet :
     ```powershell
     Remove-Item -Recurse -Force .vagrant
     ```
   - Au prochain `vagrant up`, Vagrant recréera un `.vagrant/` tout neuf et reconstruira l'environnement de zéro.


### Configurer `.env`

Ouvrir `.env` et vérifier :

```env
GROUPE_EQUIPE=15
GROUPE_RESEAU=7
NB_APP=2
POSTGRES_USER=resultats
POSTGRES_DB=resultats
POSTGRES_PASSWORD=<remplacer-par-un-vrai-mot-de-passe>
```

> Ne jamais committer `.env` avec un vrai mot de passe. Le fichier est dans `.gitignore`.

### Résultat attendu après `vagrant up`

```
bdd1    running (virtualbox)
bdd2    running (virtualbox)
app1    running (virtualbox)
app2    running (virtualbox)
lb1     running (virtualbox)
```

Endpoints vérifiables depuis le navigateur ou PowerShell :

```powershell
Invoke-RestMethod http://127.0.0.1:8080/info
Invoke-RestMethod http://127.0.0.1:8080/sante
Invoke-RestMethod "http://127.0.0.1:8080/resultat?matricule=BF-000001"
```

---

## 5. Commandes de diagnostic utiles

```powershell
# État des VM
vagrant status

# Logs d'un composant (remplacer app1 par lb1, bdd1, etc.)
vagrant ssh app1 -c "journalctl -u resultats-bf -n 30 --no-pager"

# Vérifier la réplication PostgreSQL
vagrant ssh bdd1 -c "sudo -u postgres psql -c 'SELECT client_addr, state FROM pg_stat_replication;'"

# Tester manuellement un endpoint
curl -v http://127.0.0.1:8080/sante
```
