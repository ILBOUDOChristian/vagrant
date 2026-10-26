# Verificateur d'integrite de la configuration .env / .env.exemple
param(
    [string]$FichierEnv = ".env"
)

Write-Host "Verification du fichier : $FichierEnv" -ForegroundColor Cyan

if (-not (Test-Path $FichierEnv)) {
    Write-Error "Fichier introuvable : $FichierEnv"
    exit 1
}

$lignes = Get-Content $FichierEnv
$vars = @{}
$erreurs = 0

foreach ($ligne in $lignes) {
    $clean = $ligne.Trim()
    if ($clean -eq "" -or $clean.StartsWith("#")) { continue }
    
    if ($clean -match "^([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$") {
        $key = $matches[1]
        $val = $matches[2].Trim()
        if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length - 2) }
        elseif ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Substring(1, $val.Length - 2) }
        $vars[$key] = $val
    }
}

# 1. Verification des placeholders
foreach ($k in $vars.Keys) {
    if ($vars[$k] -match "<.*>") {
        Write-Host "[ERREUR] Valeur placeholder non resolue : $k = $($vars[$k])" -ForegroundColor Red
        $erreurs++
    }
}

# 2. Verification des variables obligatoires
$obligatoires = @(
    "GROUPE_EQUIPE", "GROUPE_RESEAU", "NB_APP", "BOITE_IMAGE", "BOITE_VERSION",
    "IP_HOTE", "PORT_HOTE", "PORT_INVITE", "APP_HOST", "APP_PORT",
    "BDD_PORT", "BDD_HOST_PRIMAIRE", "BDD_HOST_SECONDAIRE",
    "MEM_BDD", "MEM_APP", "MEM_LB", "POSTGRES_USER", "POSTGRES_DB", "POSTGRES_PASSWORD"
)

foreach ($req in $obligatoires) {
    if (-not $vars.ContainsKey($req) -or [string]::IsNullOrWhiteSpace($vars[$req])) {
        Write-Host "[ERREUR] Variable obligatoire manquante ou vide : $req" -ForegroundColor Red
        $erreurs++
    }
}

# 3. Validation des bornes du sujet
if ($vars.ContainsKey("NB_APP")) {
    [int]$nbApp = $vars["NB_APP"]
    if ($nbApp -lt 2) {
        Write-Host "[ERREUR] NB_APP ($nbApp) est inferieur a 2 (contrainte officielle N >= 2)." -ForegroundColor Red
        $erreurs++
    }
}

if ($vars.ContainsKey("GROUPE_RESEAU")) {
    [int]$g = $vars["GROUPE_RESEAU"]
    if ($g -lt 1 -or $g -gt 8) {
        Write-Host "[ERREUR] GROUPE_RESEAU ($g) doit etre compris entre 1 et 8 (VirtualBox 192.168.56.0/21)." -ForegroundColor Red
        $erreurs++
    }
}

# 4. Budget memoire du socle
if ($vars.ContainsKey("MEM_BDD") -and $vars.ContainsKey("MEM_APP") -and $vars.ContainsKey("MEM_LB")) {
    $ramSocle = (2 * [int]$vars["MEM_BDD"]) + (2 * [int]$vars["MEM_APP"]) + [int]$vars["MEM_LB"]
    if ($ramSocle -gt 3072) {
        Write-Host "[ATTENTION] Le socle consomme $ramSocle Mo (depassement du budget de 3 Go)." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Budget memoire du socle conforme : $ramSocle Mo <= 3072 Mo (3 Go)." -ForegroundColor Green
    }
}

if ($erreurs -eq 0) {
    Write-Host "[SUCCES] Configuration validee avec succes !" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[ECHEC] $erreurs erreur(s) detectee(s)." -ForegroundColor Red
    exit 1
}
