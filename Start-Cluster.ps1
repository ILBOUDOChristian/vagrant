#Requires -Version 5.1
# ============================================================
#  RESULTATS-BF — Démarrage Premium du Cluster
#  Usage : .\Start-Cluster.ps1
#          .\Start-Cluster.ps1 -Provision     (force reprovision)
#          .\Start-Cluster.ps1 -Tests         (lance les tests après démarrage)
# ============================================================

param(
    [switch]$Provision,
    [switch]$Tests
)

# ── Palette de couleurs ──────────────────────────────────────
$C_RESET  = "`e[0m"
$C_BOLD   = "`e[1m"
$C_DIM    = "`e[2m"
$C_GREEN  = "`e[38;2;16;185;129m"
$C_BLUE   = "`e[38;2;99;102;241m"
$C_CYAN   = "`e[38;2;34;211;238m"
$C_YELLOW = "`e[38;2;251;191;36m"
$C_RED    = "`e[38;2;239;68;68m"
$C_GRAY   = "`e[38;2;107;114;128m"
$C_WHITE  = "`e[38;2;248;250;252m"
$C_GRAD1  = "`e[38;2;99;102;241m"
$C_GRAD2  = "`e[38;2;139;92;246m"
$C_GRAD3  = "`e[38;2;236;72;153m"

# ── Helpers ──────────────────────────────────────────────────
function Write-Blank { Write-Host "" }

function Write-Banner {
    $lines = @(
        "  ██████╗ ███████╗███████╗██╗   ██╗██╗  ████████╗ █████╗ ████████╗███████╗",
        "  ██╔══██╗██╔════╝██╔════╝██║   ██║██║  ╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝",
        "  ██████╔╝█████╗  ███████╗██║   ██║██║     ██║   ███████║   ██║   ███████╗ ",
        "  ██╔══██╗██╔══╝  ╚════██║██║   ██║██║     ██║   ██╔══██║   ██║   ╚════██║",
        "  ██║  ██║███████╗███████║╚██████╔╝███████╗██║   ██║  ██║   ██║   ███████║",
        "  ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝",
        "                         ██████╗ ███████╗                                   ",
        "                         ██╔══██╗██╔════╝                                   ",
        "                         ██████╔╝█████╗                                     ",
        "                         ██╔══██╗██╔══╝                                     ",
        "                         ██████╔╝██║                                        ",
        "                         ╚═════╝ ╚═╝                                        "
    )
    $colors = @($C_GRAD1, $C_GRAD1, $C_GRAD2, $C_GRAD2, $C_GRAD3, $C_GRAD3, $C_GRAD2, $C_GRAD2, $C_GRAD3, $C_GRAD3, $C_GRAD3, $C_GRAD3)
    Write-Blank
    for ($i = 0; $i -lt $lines.Count; $i++) {
        Write-Host "$($colors[$i])$($lines[$i])$C_RESET"
    }
    Write-Blank
    Write-Host "$C_DIM$C_CYAN        Infrastructure Haute Disponibilité — Université Joseph KI-ZERBO$C_RESET"
    Write-Host "$C_DIM$C_GRAY        Projet Groupe — M1 Informatique — IBAM$C_RESET"
    Write-Blank
}

function Write-Separator([string]$label = "") {
    $line = "─" * 72
    if ($label) {
        $pad = [math]::Max(0, [int]((72 - $label.Length - 4) / 2))
        $padStr = "─" * $pad
        Write-Host "$C_GRAY  $padStr $C_WHITE$C_BOLD $label $C_RESET$C_GRAY$padStr$C_RESET"
    } else {
        Write-Host "$C_GRAY  $line$C_RESET"
    }
}

function Write-Step([int]$n, [int]$total, [string]$msg) {
    Write-Host "$C_DIM$C_GRAY  [$n/$total]$C_RESET $C_WHITE$msg$C_RESET"
}

function Write-Ok([string]$msg) {
    Write-Host "  $C_GREEN checkmark $C_RESET $C_WHITE$msg$C_RESET"
}

function Write-Warn([string]$msg) {
    Write-Host "  $C_YELLOW  !  $C_RESET $C_YELLOW$msg$C_RESET"
}

function Write-Err([string]$msg) {
    Write-Host "  $C_RED  x  $C_RESET $C_RED$msg$C_RESET"
}

# ── Lire le PORT_HOTE depuis .env ────────────────────────────
$PORT = "8080"
$IP   = "127.0.0.1"
if (Test-Path ".\.env") {
    Get-Content ".\.env" | ForEach-Object {
        if ($_ -match "^PORT_HOTE\s*=\s*(.+)") { $PORT = $Matches[1].Trim() }
        if ($_ -match "^IP_HOTE\s*=\s*(.+)")   { $IP   = $Matches[1].Trim() }
    }
}
$FRONTEND_URL = "http://${IP}:${PORT}/"
$API_URL      = "http://${IP}:${PORT}"

# ════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════
Clear-Host
Write-Banner

Write-Separator "DEMARRAGE DU CLUSTER"
Write-Blank

# ── Vérif Vagrant ────────────────────────────────────────────
Write-Step 1 4 "Verification de l'environnement Vagrant..."
try {
    $vagrantVersion = (vagrant --version 2>&1) -join ""
    Write-Ok "Vagrant detecte : $vagrantVersion"
} catch {
    Write-Err "Vagrant n'est pas installe ou pas dans le PATH."
    exit 1
}

# ── Démarrage VMs ────────────────────────────────────────────
Write-Blank
Write-Step 2 4 "Demarrage des machines virtuelles (vagrant up)..."
Write-Blank

$vagrantArgs = @("up")
if ($Provision) { $vagrantArgs += "--provision" }

$proc = Start-Process -FilePath "vagrant" -ArgumentList $vagrantArgs `
    -NoNewWindow -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Blank
    Write-Err "vagrant up a echoue (code $($proc.ExitCode))."
    Write-Warn "Verifiez les logs ci-dessus. Essayez : vagrant up --provision"
    exit $proc.ExitCode
}

# ── Vérification des VMs ─────────────────────────────────────
Write-Blank
Write-Step 3 4 "Verification du statut des noeuds..."
Write-Blank

$vmStatus = vagrant status 2>&1
$vms = @("bdd1","bdd2","app1","app2","lb1")
foreach ($vm in $vms) {
    $joined = ($vmStatus -join " ")
    if ($joined -match "${vm}\s+running") {
        Write-Ok "$vm           running"
    } else {
        Write-Warn "$vm           etat inconnu"
    }
}

# ── Test de l'API ─────────────────────────────────────────────
Write-Blank
Write-Step 4 4 "Verification de la disponibilite de l'API..."
Write-Blank

$apiReady = $false
$maxRetries = 12
for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        $resp = Invoke-RestMethod -Uri "$API_URL/sante" -TimeoutSec 3 -ErrorAction Stop
        if ($resp.statut) {
            $apiReady = $true
            break
        }
    } catch {}
    Write-Host "  $C_DIM$C_GRAY  Attente API... tentative $attempt/$maxRetries$C_RESET"
    Start-Sleep -Seconds 2
}

if ($apiReady) {
    Write-Ok "API disponible sur $API_URL"
} else {
    Write-Warn "API non confirmee (verifiez dans quelques instants)"
}

# ════════════════════════════════════════════════════════════
#  TABLEAU DE BORD POST-DEMARRAGE
# ════════════════════════════════════════════════════════════
Write-Blank
Write-Separator "CLUSTER PRET"
Write-Blank

Write-Host "  $C_BOLD$C_WHITE  Votre infrastructure RESULTATS-BF est operationnelle.$C_RESET"
Write-Blank
Write-Host "  $C_GRAY+------------------------------------------------------------------+$C_RESET"
Write-Host "  $C_GRAY|$C_RESET $C_BOLD$C_WHITE  ACCES AU PORTAIL$C_RESET                                               $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET                                                                  $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_BOLD$C_GREEN [WEB]$C_RESET  Frontend SaaS  : $C_BOLD$C_CYAN$FRONTEND_URL$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_BOLD$C_BLUE [API]$C_RESET  HAProxy Info   : $C_BOLD$C_CYAN$API_URL/info$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_BOLD$C_YELLOW [SAN]$C_RESET  Sonde sante    : $C_BOLD$C_CYAN$API_URL/sante$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_BOLD$C_GRAD3 [RES]$C_RESET  Resultats BF   : $C_BOLD$C_CYAN$API_URL/resultat?matricule=BF-000006$C_RESET"
Write-Host "  $C_GRAY|$C_RESET                                                                  $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY+------------------------------------------------------------------+$C_RESET"
Write-Blank
Write-Host "  $C_GRAY+------------------------------------------------------------------+$C_RESET"
Write-Host "  $C_GRAY|$C_RESET $C_BOLD$C_WHITE  SCENARIOS DE VALIDATION DISPONIBLES$C_RESET                           $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET                                                                  $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[V1]$C_RESET  Repartition de charge HAProxy           $C_DIM$C_GRAY20 requetes$C_RESET         $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[V2]$C_RESET  Panne applicative et eviction < 5s      $C_DIM$C_GRAYcrash app1$C_RESET         $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[V3]$C_RESET  Test de charge Apache Bench             $C_DIM$C_GRAY200 req c=10$C_RESET        $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[V4]$C_RESET  Bascule BDD (bdd1 vers bdd2)            $C_DIM$C_GRAYPostgreSQL HA$C_RESET       $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[V6]$C_RESET  Panne repartiteur lb1 (VRRP/E1)         $C_DIM$C_GRAYKeepalived$C_RESET          $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET    $C_CYAN[E4]$C_RESET  Deploiement sans coupure (rolling)      $C_DIM$C_GRAYHAProxy API$C_RESET         $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY|$C_RESET                                                                  $C_GRAY|$C_RESET"
Write-Host "  $C_GRAY+------------------------------------------------------------------+$C_RESET"
Write-Blank

# ════════════════════════════════════════════════════════════
#  MENU DE CHOIX INTERACTIF
# ════════════════════════════════════════════════════════════
if (-not $Tests) {
    Write-Separator "QUE VOULEZ-VOUS FAIRE ?"
    Write-Blank
    Write-Host "  $C_BOLD$C_WHITE [1]$C_RESET  $C_GREEN [WEB]  Ouvrir le portail SaaS dans le navigateur$C_RESET"
    Write-Host "         $C_GRAY$FRONTEND_URL$C_RESET"
    Write-Blank
    Write-Host "  $C_BOLD$C_WHITE [2]$C_RESET  $C_BLUE [TER]  Lancer les tests de validation dans ce terminal$C_RESET"
    Write-Host "         $C_GRAY.\tests\Lancer-Tests.ps1 (menu interactif)$C_RESET"
    Write-Blank
    Write-Host "  $C_BOLD$C_WHITE [3]$C_RESET  $C_YELLOW [ALL]  Les deux (navigateur + menu tests)$C_RESET"
    Write-Blank
    Write-Host "  $C_BOLD$C_WHITE [0]$C_RESET  $C_GRAY [FIN]  Terminer (rester en ligne de commande)$C_RESET"
    Write-Blank
    Write-Separator

    $done = $false
    while (-not $done) {
        Write-Host ""
        $choice = Read-Host "  Votre choix [1/2/3/0]"
        switch ($choice.Trim()) {
            "1" {
                Write-Blank
                Write-Ok "Ouverture de $FRONTEND_URL dans votre navigateur..."
                Start-Process $FRONTEND_URL
                Write-Blank
                Write-Host "  $C_GRAY  Portail ouvert. Pour les tests en CLI :$C_RESET"
                Write-Host "  $C_CYAN  .\tests\Lancer-Tests.ps1$C_RESET"
                $done = $true
            }
            "2" {
                Write-Blank
                Write-Ok "Lancement du menu interactif de tests..."
                Write-Blank
                & ".\tests\Lancer-Tests.ps1"
                $done = $true
            }
            "3" {
                Write-Blank
                Write-Ok "Ouverture du portail dans le navigateur..."
                Start-Process $FRONTEND_URL
                Start-Sleep -Milliseconds 800
                Write-Ok "Lancement du menu de tests dans ce terminal..."
                Write-Blank
                & ".\tests\Lancer-Tests.ps1"
                $done = $true
            }
            "0" {
                Write-Blank
                Write-Host "  $C_GRAY  A bientot ! Le cluster tourne en arriere-plan.$C_RESET"
                $done = $true
            }
            default {
                Write-Warn "Choix invalide. Entrez 1, 2, 3 ou 0."
            }
        }
    }
} else {
    Write-Blank
    Write-Ok "Mode --Tests active. Lancement immediat du menu..."
    Write-Blank
    & ".\tests\Lancer-Tests.ps1"
}

Write-Blank
Write-Separator
Write-Host "  $C_DIM$C_GRAY  Pour arreter : vagrant halt    |   Pour detruire : vagrant destroy$C_RESET"
Write-Separator
Write-Blank
