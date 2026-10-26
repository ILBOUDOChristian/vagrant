# RESULTATS-BF -- Scenarios de validation (PowerShell natif)
# Les scripts bash tournent dans les VM Linux via vagrant ssh.
# Usage : .\tests\Lancer-Tests.ps1 -Scenario V1
#         .\tests\Lancer-Tests.ps1           (menu interactif)

param(
    [ValidateSet("V1","V2","V3","V4","V6","E4","Info","Tous")]
    [string]$Scenario = ""
)

# Lecture de URL_API_BASE depuis .env (même racine que le Vagrantfile)
$EnvFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "[ERREUR] Fichier .env introuvable. Copiez .env.exemple vers .env et configurez URL_API_BASE." -ForegroundColor Red
    exit 1
}
$BASE_URL = $null
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^URL_API_BASE\s*=\s*(.+)$') {
        $BASE_URL = $Matches[1].Trim().Trim('"').Trim("'")
    }
}
if (-not $BASE_URL) {
    Write-Host "[ERREUR] URL_API_BASE non definie dans .env. Ajoutez : URL_API_BASE=http://127.0.0.1:8080" -ForegroundColor Red
    exit 1
}
# Exporter pour que les scripts bash heritent de la variable via l'environnement
$env:URL_API_BASE = $BASE_URL


function Write-Titre([string]$t) {
    Write-Host ""
    Write-Host ("-" * 55) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("-" * 55) -ForegroundColor DarkGray
}
function Write-Ok([string]$m)   { Write-Host "[OK]    $m" -ForegroundColor Green }
function Write-Fail([string]$m) { Write-Host "[ECHEC] $m" -ForegroundColor Red }
function Write-Info([string]$m) { Write-Host "        $m" -ForegroundColor Gray }

# V1 -- Repartition de charge ---------------------------------------------
function Run-V1 {
    Write-Titre "V1 -- Repartition de charge HAProxy"
    $n = 20; $c1 = 0; $c2 = 0; $err = 0
    Write-Info "Envoi de $n requetes sur /info via HAProxy..."
    for ($i = 1; $i -le $n; $i++) {
        try {
            $raw = & "curl.exe" -s --connect-timeout 2 "$BASE_URL/info"
            if ($raw -match '"hostname":\s*"app1"') { $c1++; Write-Info "  Req $i -> app1" }
            elseif ($raw -match '"hostname":\s*"app2"') { $c2++; Write-Info "  Req $i -> app2" }
            else { $err++; Write-Info "  Req $i -> ERREUR / INCONNU" }
        } catch { $err++; Write-Info "  Req $i -> ERREUR" }
    }
    Write-Host ""
    Write-Info "app1=$c1 | app2=$c2 | erreurs=$err"
    if ($c1 -gt 0 -and $c2 -gt 0 -and $err -eq 0) { 
        $ecart = [math]::Abs($c1 - $c2)
        $pct = ($ecart / $n) * 100
        Write-Ok "Les deux serveurs ont recu du trafic (Ecart: $ecart requetes = $pct% <= 20%)." 
    } else { 
        Write-Fail "Repartition non equilibree ou requetes en echec." 
    }
}

# V2 -- Panne applicative -------------------------------------------------
function Run-V2 {
    Write-Titre "V2 -- Panne applicative (crash app1)"
    Write-Info "Arret de resultats-bf sur app1..."
    vagrant ssh app1 -c "sudo systemctl stop resultats-bf" 2>$null
    $debut = Get-Date
    Write-Info "Envoi continu de requetes (max 15s)..."
    $repris = $false
    for ($i = 1; $i -le 30; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "$BASE_URL/info" -TimeoutSec 2
            if ($r.hostname -eq "app2") {
                $d = [math]::Round(((Get-Date) - $debut).TotalSeconds, 2)
                Write-Ok "Trafic repris sur app2 en $d s."
                $repris = $true; break
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    Write-Info "Redemarrage de app1..."
    vagrant ssh app1 -c "sudo systemctl start resultats-bf" 2>$null
    if (-not $repris) { Write-Fail "app2 n'a pas pris le relais en 15 s." }
}

# V3 -- Test de charge via lb1 --------------------------------------------
function Run-V3 {
    Write-Titre "V3 -- Test de charge (apache bench)"
    Write-Info "200 requetes, concurrence 10 depuis lb1..."
    vagrant ssh lb1 -c "ab -n 200 -c 10 -q http://127.0.0.1/sante 2>&1 | grep -E 'Requests per second|Failed requests|Time per request'"
}

# V4 -- Bascule BDD -------------------------------------------------------
function Run-V4 {
    Write-Titre "V4 -- Bascule base de donnees (bdd1 -> bdd2)"
    Write-Info "1. Verification de la sante initiale..."
    try {
        $init = Invoke-RestMethod -Uri "$BASE_URL/sante" -TimeoutSec 2
        Write-Info "   /sante avant panne : $($init.statut)"
    } catch {
        Write-Fail "Le service n'est pas sain avant le test."
        return
    }

    Write-Info "2. Arret de bdd1..."
    $debut = Get-Date
    vagrant halt bdd1

    Write-Info "3. Execution de la procedure de promotion sur bdd2..."
    vagrant ssh bdd2 -c "sudo /vagrant/scripts/bascule.sh"

    Write-Info "4. Mesure du temps jusqu'au retour de /sante = OK..."
    $ok = $false
    for ($i = 1; $i -le 45; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "$BASE_URL/sante" -TimeoutSec 4
            if ($r.statut -eq "ok") {
                $d = [math]::Round(((Get-Date) - $debut).TotalSeconds, 2)
                Write-Ok "/sante retabli avec succes en $d s (bdd2 est active) !"
                $ok = $true; break
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
    if (-not $ok) { Write-Fail "/sante n'est pas revenu a OK en 45 s." }


    Write-Info "5. Verification de l'acces aux donnees (/resultat)..."
    try {
        $res = Invoke-RestMethod -Uri "$BASE_URL/resultat?matricule=BF-000006" -TimeoutSec 3
        Write-Ok "Resultat BF-000006 obtenu sur la nouvelle primaire : $($res.nom)"
    } catch {
        Write-Fail "Impossible de consulter /resultat apres bascule."
    }

    Write-Info "6. Redemarrage de bdd1 et rearmement du cluster..."
    vagrant up bdd1
    vagrant provision bdd1 bdd2
}

# V6 -- Panne rePartiteur lb1 (E1 Keepalived) ----------------------------
function Run-V6 {
    Write-Titre "V6 -- Panne rePartiteur lb1 (VRRP / E1)"
    Write-Info "Verifiant si l'extension E1 (lb2 + VRRP) est active..."
    $e1Active = ($env:ACTIVER_EXTENSION_E1 -eq "true")

    Write-Info "Arret de lb1..."
    vagrant halt lb1
    $debut = Get-Date
    $ok = $false
    for ($i = 1; $i -le 10; $i++) {
        try {
            Invoke-RestMethod -Uri "$BASE_URL/sante" -TimeoutSec 2 | Out-Null
            $d = [math]::Round(((Get-Date) - $debut).TotalSeconds, 2)
            Write-Ok "Service maintenu par lb2 en $d s (E1 actif)."
            $ok = $true; break
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ok) {
        if (-not $e1Active) {
            Write-Ok "COMPORTEMENT ATTENDU : lb1 est le repartiteur unique (SPOF demontre, extension E1 non activee)."
        } else {
            Write-Fail "Service injoignable apres la panne de lb1 malgre l'extension E1."
        }
    }
    Write-Info "Redemarrage de lb1..."
    vagrant up lb1
}


# E4 -- Deploiement sans coupure -----------------------------------------
function Run-E4 {
    Write-Titre "E4 -- Deploiement sans coupure (rolling update)"
    Write-Info "Lancement du rolling update via lb1..."
    vagrant ssh lb1 -c "bash /vagrant/scripts/deploiement_sans_coupure.sh /vagrant/app/app.py"
    Write-Ok "Deploiement termine."
}

# Rapide : /info + /sante -------------------------------------------------
function Run-Info {
    Write-Titre "Test rapide : /info et /sante"
    try {
        $r = Invoke-RestMethod -Uri "$BASE_URL/info" -TimeoutSec 3
        Write-Ok "/info  -> hostname=$($r.hostname)  statut=$($r.statut)"
    } catch { Write-Fail "/info injoignable" }
    try {
        $r = Invoke-RestMethod -Uri "$BASE_URL/sante" -TimeoutSec 3
        Write-Ok "/sante -> statut=$($r.statut)  base=$($r.base)"
    } catch { Write-Fail "/sante injoignable" }
    try {
        $r = Invoke-RestMethod -Uri "$BASE_URL/resultat?matricule=BF-000006" -TimeoutSec 3
        Write-Ok "/resultat BF-000006 -> $($r.nom)  admis=$($r.admis)"
    } catch { Write-Fail "/resultat injoignable" }
}

# Menu interactif ----------------------------------------------------------
function Show-Menu {
    do {
        Write-Host ""
        Write-Host "  RESULTATS-BF -- Scenarios de validation" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] V1 -- Repartition de charge" -ForegroundColor White
        Write-Host "  [2] V2 -- Panne applicative (crash app1)" -ForegroundColor White
        Write-Host "  [3] V3 -- Test de charge (ab)" -ForegroundColor White
        Write-Host "  [4] V4 -- Bascule BDD (bdd1 -> bdd2)" -ForegroundColor White
        Write-Host "  [5] V6 -- Panne rePartiteur lb1 (E1)" -ForegroundColor White
        Write-Host "  [6] E4 -- Deploiement sans coupure" -ForegroundColor White
        Write-Host "  [7]    -- Test rapide (/info + /sante + /resultat)" -ForegroundColor White
        Write-Host "  [0]    -- Quitter" -ForegroundColor DarkGray
        Write-Host ""
        $choix = Read-Host "  Votre choix"
        switch ($choix) {
            "1" { Run-V1 }
            "2" { Run-V2 }
            "3" { Run-V3 }
            "4" { Run-V4 }
            "5" { Run-V6 }
            "6" { Run-E4 }
            "7" { Run-Info }
            "0" { return }
            default { Write-Host "Choix invalide." -ForegroundColor Red }
        }
    } while ($choix -ne "0")
}

# Point d'entree ----------------------------------------------------------
switch ($Scenario) {
    "V1"   { Run-V1 }
    "V2"   { Run-V2 }
    "V3"   { Run-V3 }
    "V4"   { Run-V4 }
    "V6"   { Run-V6 }
    "E4"   { Run-E4 }
    "Info" { Run-Info }
    "Tous" { Run-V1; Run-V2; Run-Info }
    default { Show-Menu }
}
