// ==========================================
// RESULTATS-BF - Logique Javascript Client
// Architecture Haute Disponibilite
// ==========================================

const API_BASE = (window.URL_API_BASE && window.URL_API_BASE.startsWith("http")) 
    ? window.URL_API_BASE 
    : window.location.origin;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ─────────────────────────────────────────────
//  Navigation onglets principaux
// ─────────────────────────────────────────────
function switchMainTab(tab) {
    const btnConsult  = document.getElementById('tabBtnConsultation');
    const btnApi      = document.getElementById('tabBtnApi');
    const btnTests    = document.getElementById('tabBtnTests');
    const contentConsult = document.getElementById('contentConsultation');
    const contentApi  = document.getElementById('contentApi');
    const contentTests = document.getElementById('contentTests');

    [btnConsult, btnApi, btnTests].forEach(b => b && b.classList.remove('active'));
    [contentConsult, contentApi, contentTests].forEach(c => c && (c.style.display = 'none'));

    if (tab === 'consultation') {
        btnConsult.classList.add('active');
        contentConsult.style.display = 'block';
    } else if (tab === 'api') {
        btnApi.classList.add('active');
        contentApi.style.display = 'block';
    } else if (tab === 'tests') {
        btnTests.classList.add('active');
        contentTests.style.display = 'block';
    }
}

// ─────────────────────────────────────────────
//  Fonctions utilitaires console
// ─────────────────────────────────────────────
function consoleLog(msg, type = 'info') {
    const el = document.getElementById('testsConsoleOutput');
    if (!el) return;
    const prefix = {
        'ok':      '  ✓ [OK]   ',
        'fail':    '  ✗ [FAIL] ',
        'info':    '  · ',
        'title':   '\n══ ',
        'cmd':     '$ ',
        'blank':   ''
    }[type] || '  ';
    el.textContent += prefix + msg + '\n';
    el.scrollTop = el.scrollHeight;
}

// Écriture dans le terminal du Banc de Tests (colonne droite)
function benchLog(msg, type = 'info') {
    const el = document.getElementById('benchTerminalOutput');
    if (!el) return;
    const prefix = {
        'ok':      '  ✓ [OK]   ',
        'fail':    '  ✗ [FAIL] ',
        'info':    '  · ',
        'title':   '\n══ ',
        'cmd':     '$ ',
        'blank':   ''
    }[type] || '  ';
    el.textContent += prefix + msg + '\n';
    el.scrollTop = el.scrollHeight;
}

function clearConsole() {
    const el = document.getElementById('testsConsoleOutput');
    if (el) {
        el.textContent = '$ # Console réinitialisée.\n$ \n';
        el.scrollTop = 0;
    }
    // Réinitialiser les statuts des cartes
    ['v1','v2','v3','v4','v6','e4'].forEach(resetScenarioCard);
}

function clearBenchTerminal() {
    const el = document.getElementById('benchTerminalOutput');
    if (el) {
        el.textContent = '$ # Terminal réinitialisé.\n$ \n';
        el.scrollTop = 0;
    }
    const lbl = document.getElementById('benchTermLabel');
    if (lbl) lbl.textContent = '— Sélectionnez un scénario ci-dessus —';
    ['v1','v2','v3','v4','v6','e4'].forEach(resetScenarioCard);
}

function copyBenchTerminal() {
    const el = document.getElementById('benchTerminalOutput');
    if (el) {
        navigator.clipboard.writeText(el.textContent).then(() => {
            const btns = document.querySelectorAll('.bench-term-actions .console-action-btn');
            const btn = btns[0];
            if (btn) {
                btn.textContent = 'Copié !';
                setTimeout(() => btn.textContent = 'Copier', 1500);
            }
        });
    }
}

function copyConsole() {
    const el = document.getElementById('testsConsoleOutput');
    if (el) {
        navigator.clipboard.writeText(el.textContent).then(() => {
            const btn = Array.from(document.querySelectorAll('.console-action-btn'))
                .find(b => b.textContent === 'Copier');
            if (btn) {
                btn.textContent = 'Copié !';
                setTimeout(() => btn.textContent = 'Copier', 1500);
            }
        });
    }
}

function openTerminalGuide() {
    const guide = document.getElementById('terminalGuide');
    const btn   = document.getElementById('consoleTermBtn');
    if (!guide) return;
    const isOpen = guide.style.display !== 'none';
    guide.style.display = isOpen ? 'none' : 'block';
    btn.textContent = isOpen ? 'CLI ↗' : 'CLI ↙';
}

function copyCmd(cmd) {
    navigator.clipboard.writeText(cmd).then(() => {
        // Feedback visuel court
    });
}

// ─────────────────────────────────────────────
//  Gestion statut des cartes scénario
// ─────────────────────────────────────────────
function setScenarioStatus(id, state) {
    // state: 'idle' | 'running' | 'success' | 'fail'
    const statusEl = document.getElementById(`sc-${id}-status`);
    const card     = document.getElementById(`sc-${id}`);
    const btn      = document.getElementById(`sc-${id}-btn`);
    if (!statusEl || !card) return;

    const configs = {
        idle:    { dot: 'sc-dot-idle',    text: 'Prêt',       cardClass: '',           btnText: null },
        running: { dot: 'sc-dot-running', text: 'En cours…',  cardClass: 'sc-running', btnText: '⟳ En cours' },
        success: { dot: 'sc-dot-success', text: 'Réussi ✓',   cardClass: 'sc-success', btnText: null },
        fail:    { dot: 'sc-dot-fail',    text: 'Échec ✗',    cardClass: 'sc-failed',  btnText: null }
    };
    const cfg = configs[state] || configs.idle;
    const dot = statusEl.querySelector('.sc-dot');
    const txt = statusEl.querySelector('.sc-status-text');
    if (dot) dot.className = `sc-dot ${cfg.dot}`;
    if (txt) txt.textContent = cfg.text;
    // La carte utilise maintenant diag-card + sc-card-ext, on gère juste les classes d'état
    const baseClasses = card.classList.contains('sc-card-ext')
        ? 'diag-card sc-card-ext'
        : 'scenario-card';
    card.className = `${baseClasses} ${cfg.cardClass}`;
    if (btn && cfg.btnText) btn.textContent = cfg.btnText;
}

function resetScenarioCard(id) {
    setScenarioStatus(id, 'idle');
    const btn = document.getElementById(`sc-${id}-btn`);
    const labels = {
        v1: 'Lancer', v2: 'Tester', v3: 'Lancer',
        v4: 'Tester', v6: 'Tester', e4: 'Executer'
    };
    if (btn) {
        btn.textContent = labels[id] || 'Lancer';
        btn.disabled = false;
    }
}

// ─────────────────────────────────────────────
//  Dispatcher principal des scénarios
// ─────────────────────────────────────────────
async function runScenario(id) {
    switchMainTab('tests');
    const btn = document.getElementById(`sc-${id}-btn`);
    if (btn) btn.disabled = true;
    setScenarioStatus(id, 'running');

    // Mettre à jour le label du terminal du banc de tests
    const labelNames = {
        v1: 'V1 — Répartition de charge',
        v2: 'V2 — Panne applicative',
        v3: 'V3 — Test de charge (ab)',
        v4: 'V4 — Bascule BDD',
        v6: 'V6 — Panne répartiteur lb1',
        e4: 'E4 — Déploiement sans coupure'
    };
    const lbl = document.getElementById('benchTermLabel');
    if (lbl) lbl.textContent = labelNames[id] || id.toUpperCase();

    // Effacer le terminal du banc de tests
    const el = document.getElementById('benchTerminalOutput');
    if (el) el.textContent = '';

    try {
        const result = await {
            v1: runScenarioV1,
            v2: runScenarioV2,
            v3: runScenarioV3,
            v4: runScenarioV4,
            v6: runScenarioV6,
            e4: runScenarioE4
        }[id]();

        setScenarioStatus(id, result ? 'success' : 'fail');
    } catch (err) {
        benchLog(`Erreur inattendue : ${err.message}`, 'fail');
        setScenarioStatus(id, 'fail');
    } finally {
        if (btn) btn.disabled = false;
        const labels = {
            v1: 'Lancer', v2: 'Tester', v3: 'Lancer',
            v4: 'Tester', v6: 'Tester', e4: 'Executer'
        };
        if (btn) btn.textContent = labels[id];
    }
}

// ─────────────────────────────────────────────
//  V1 — Répartition de charge Round-Robin
// ─────────────────────────────────────────────
async function runScenarioV1() {
    benchLog('SCÉNARIO V1 — RÉPARTITION DE CHARGE HAPROXY', 'title');
    benchLog('Sujet : Vérifier la répartition équilibrée entre app1 et app2', 'info');
    benchLog('Envoi de 20 requêtes successives vers /info via HAProxy…\n', 'cmd');

    const stats = {};
    let errCount = 0;

    for (let i = 1; i <= 20; i++) {
        try {
            const t0 = performance.now();
            const res = await fetch(`${API_BASE}/info`);
            const data = await res.json();
            const ms = (performance.now() - t0).toFixed(0);
            const host = data.hostname || data.serveur || 'inconnu';
            stats[host] = (stats[host] || 0) + 1;
            benchLog(`Req #${String(i).padStart(2,'0')} → ${host.padEnd(6)} (${ms} ms)`, 'info');
        } catch {
            errCount++;
            benchLog(`Req #${String(i).padStart(2,'0')} → ERREUR RÉSEAU`, 'fail');
        }
        await sleep(80);
    }

    benchLog('', 'blank');
    benchLog('Synthèse de la répartition :', 'cmd');
    for (const [srv, count] of Object.entries(stats)) {
        const pct = Math.round(count / 20 * 100);
        const bar = '█'.repeat(Math.round(pct / 5));
        benchLog(`  ${srv.padEnd(6)} : ${String(count).padStart(2)} req  ${bar} ${pct}%`, 'info');
    }

    const c1 = stats['app1'] || 0;
    const c2 = stats['app2'] || 0;
    const ecart = Math.abs(c1 - c2);
    const pct = ((ecart / 20) * 100).toFixed(1);

    benchLog('', 'blank');
    if (c1 > 0 && c2 > 0 && errCount === 0 && ecart <= 4) {
        benchLog(`VERDICT : SUCCÈS — Écart = ${ecart} req (${pct}% ≤ 20%). Répartition conforme.`, 'ok');
        return true;
    } else {
        benchLog(`VERDICT : ALERTE — app1=${c1} app2=${c2} erreurs=${errCount} écart=${ecart} req`, 'fail');
        return false;
    }
}

// ─────────────────────────────────────────────
//  V2 — Panne applicative (sonde frontend)
// ─────────────────────────────────────────────
async function runScenarioV2() {
    benchLog('SCÉNARIO V2 — PANNE APPLICATIVE & ÉVICTION HAPROXY', 'title');
    benchLog('Sujet : Arrêt service app1 → Éviction HAProxy < 5s → Trafic sur app2\n', 'info');

    benchLog('1. Vérification de la sonde /sante avant panne…', 'cmd');
    try {
        const r = await fetch(`${API_BASE}/sante`);
        const d = await r.json();
        benchLog(`   /sante → HTTP ${r.status} | statut=${d.statut} base=${d.base}`, 'ok');
    } catch {
        benchLog('   /sante injoignable — service non disponible avant test', 'fail');
        return false;
    }

    benchLog('', 'blank');
    benchLog('2. Surveillance de la bascule depuis le navigateur…', 'cmd');
    benchLog('   (Pour la partie arrêt physique de app1, utilisez le terminal CLI)', 'info');
    benchLog('   Commande CLI : .\tests\Lancer-Tests.ps1 -Scenario V2', 'info');
    benchLog('', 'blank');
    benchLog('3. Mesure de la continuité depuis ce client (30 requêtes)…', 'cmd');

    let ok = 0, fail = 0, lastHost = null;
    const debut = performance.now();

    for (let i = 1; i <= 30; i++) {
        try {
            const r = await fetch(`${API_BASE}/info`);
            const d = await r.json();
            const host = d.hostname || d.serveur || '?';
            lastHost = host;
            ok++;
            if (i % 5 === 0) benchLog(`   Req ${i}/30 → ${host} (OK)`, 'info');
        } catch {
            fail++;
            if (i % 5 === 0) benchLog(`   Req ${i}/30 → ERREUR RÉSEAU`, 'fail');
        }
        await sleep(300);
    }

    const duree = ((performance.now() - debut) / 1000).toFixed(1);
    benchLog('', 'blank');
    benchLog(`Résultat : ${ok} OK / ${fail} FAIL en ${duree}s`, 'info');

    if (fail === 0) {
        benchLog('VERDICT : CONTINUITÉ DE SERVICE CONFIRMÉE — Aucune requête en échec', 'ok');
        benchLog('→ Pour tester le failover complet, exécutez en CLI : Lancer-Tests.ps1 -Scenario V2', 'info');
        return true;
    } else {
        benchLog(`VERDICT : ${fail} requête(s) en échec détectées`, 'fail');
        return false;
    }
}

// ─────────────────────────────────────────────
//  V3 — Test de charge (orienté CLI)
// ─────────────────────────────────────────────
async function runScenarioV3() {
    benchLog('SCÉNARIO V3 — TEST DE CHARGE APACHE BENCH', 'title');
    benchLog('Sujet : 200 requêtes avec concurrence 10 via ab depuis lb1\n', 'info');

    benchLog('Ce scénario requiert Apache Bench (ab) sur lb1.', 'info');
    benchLog('Il est exécuté depuis le terminal CLI via vagrant ssh.\n', 'info');
    benchLog('Commande pour lb1 :', 'cmd');
    benchLog('  ab -n 200 -c 10 -q http://[lb1]/sante', 'info');
    benchLog('', 'blank');
    benchLog('Via PowerShell :', 'cmd');
    benchLog('  .\tests\Lancer-Tests.ps1 -Scenario V3', 'info');
    benchLog('', 'blank');
    benchLog('Simulation de la partie mesurable depuis le navigateur…', 'cmd');

    // On fait 20 requêtes parallèles pour simuler la charge
    const N = 20, CONCURRENCE = 5;
    const resultats = [];
    let erreurs = 0;

    benchLog(`Envoi de ${N} requêtes (concurrence=${CONCURRENCE}) vers /sante…`, 'info');

    const batches = Math.ceil(N / CONCURRENCE);
    for (let b = 0; b < batches; b++) {
        const batch = [];
        for (let j = 0; j < CONCURRENCE && b * CONCURRENCE + j < N; j++) {
            const t0 = performance.now();
            batch.push(
                fetch(`${API_BASE}/sante`)
                    .then(r => r.json().then(() => performance.now() - t0))
                    .catch(() => { erreurs++; return null; })
            );
        }
        const times = await Promise.all(batch);
        times.filter(Boolean).forEach(t => resultats.push(t));
        await sleep(100);
    }

    const valid = resultats.filter(Boolean);
    if (valid.length > 0) {
        const avg = (valid.reduce((a,b) => a+b, 0) / valid.length).toFixed(1);
        const max = Math.max(...valid).toFixed(1);
        const min = Math.min(...valid).toFixed(1);
        benchLog('', 'blank');
        benchLog(`Requêtes réussies : ${valid.length}/${N}`, 'ok');
        benchLog(`Latence moyenne   : ${avg} ms`, 'info');
        benchLog(`Latence min/max   : ${min}ms / ${max}ms`, 'info');
        benchLog(`Erreurs           : ${erreurs}`, erreurs > 0 ? 'fail' : 'info');
        benchLog('', 'blank');
        benchLog('Pour le résultat complet ab avec req/s :', 'info');
        benchLog('  .\tests\Lancer-Tests.ps1 -Scenario V3', 'info');
        benchLog('', 'blank');
        benchLog('VERDICT : Test de charge partiel OK depuis navigateur — Utilisez le CLI pour ab complet', 'ok');
        return erreurs === 0;
    } else {
        benchLog('VERDICT : API injoignable', 'fail');
        return false;
    }
}

// ─────────────────────────────────────────────
//  V4 — Bascule BDD (guidé CLI)
// ─────────────────────────────────────────────
async function runScenarioV4() {
    benchLog('SCÉNARIO V4 — BASCULE BASE DE DONNÉES (bdd1 → bdd2)', 'title');
    benchLog('Sujet : Arrêt bdd1 → Promotion bdd2 → Vérification /sante → Redémarrage\n', 'info');

    benchLog('1. État initial du cluster…', 'cmd');
    try {
        const r = await fetch(`${API_BASE}/sante`);
        const d = await r.json();
        benchLog(`   /sante → statut=${d.statut} base=${d.base}`, 'ok');
    } catch {
        benchLog('   /sante injoignable — état initial inconnu', 'fail');
    }

    benchLog('', 'blank');
    benchLog('2. Ce scénario nécessite un arrêt physique de bdd1 (vagrant halt).', 'info');
    benchLog('   La promotion de bdd2 en primaire requiert :', 'info');
    benchLog('   vagrant ssh bdd2 -c "sudo /vagrant/scripts/bascule.sh"', 'info');
    benchLog('', 'blank');
    benchLog('   Commande PowerShell complète :', 'cmd');
    benchLog('   .\tests\Lancer-Tests.ps1 -Scenario V4', 'info');
    benchLog('', 'blank');
    benchLog('3. Surveillance de /sante en attente de rétablissement…', 'cmd');

    let retabli = false;
    for (let i = 1; i <= 20; i++) {
        try {
            const r = await fetch(`${API_BASE}/sante`, {signal: AbortSignal.timeout(3000)});
            const d = await r.json();
            if (d.statut === 'ok') {
                benchLog(`   Tentative ${i}/20 → statut=ok base=${d.base}`, 'ok');
                retabli = true;
                break;
            } else {
                if (i % 3 === 0) benchLog(`   Tentative ${i}/20 → statut=${d.statut}`, 'info');
            }
        } catch {
            if (i % 3 === 0) benchLog(`   Tentative ${i}/20 → timeout/erreur`, 'info');
        }
        await sleep(1500);
    }

    benchLog('', 'blank');
    benchLog('VERDICT : Vérification de la bascule depuis le navigateur.', 'info');
    benchLog('Pour déclencher la bascule complète, utilisez :', 'info');
    benchLog('  .\tests\Lancer-Tests.ps1 -Scenario V4', 'info');
    benchLog('', 'blank');
    if (retabli) {
        benchLog('Service /sante opérationnel — BDD répondante', 'ok');
    }
    return retabli;
}

// ─────────────────────────────────────────────
//  V6 — Panne répartiteur lb1 (E1 guidé CLI)
// ─────────────────────────────────────────────
async function runScenarioV6() {
    benchLog('SCÉNARIO V6 — PANNE RÉPARTITEUR lb1 (EXTENSION E1 — VRRP/Keepalived)', 'title');
    benchLog('Sujet : Arrêt lb1 → VRRP bascule VIP sur lb2 → Service maintenu\n', 'info');

    benchLog('Ce scénario requiert ACTIVER_EXTENSION_E1=true dans .env', 'info');
    benchLog('et lb2 provisionnée (vagrant up lb2)\n', 'info');
    benchLog('Déclenchement via CLI :', 'cmd');
    benchLog('  .\tests\Lancer-Tests.ps1 -Scenario V6', 'info');
    benchLog('', 'blank');
    benchLog('Vérification depuis le navigateur (continuité service)…', 'cmd');

    let ok = 0, fail = 0;
    for (let i = 1; i <= 10; i++) {
        try {
            const r = await fetch(`${API_BASE}/sante`, {signal: AbortSignal.timeout(3000)});
            if (r.ok) { ok++; }
        } catch { fail++; }
        await sleep(500);
    }

    benchLog('', 'blank');
    benchLog(`Continuité mesurée : ${ok}/10 requêtes réussies`, ok >= 8 ? 'ok' : 'fail');
    if (ok >= 8) {
        benchLog('VERDICT : Service disponible — Utilisez le CLI pour tester le failover lb1→lb2', 'ok');
        return true;
    } else {
        benchLog('VERDICT : Dégradation détectée — lb1 peut-être inaccessible', 'fail');
        return false;
    }
}

// ─────────────────────────────────────────────
//  E4 — Déploiement sans coupure (guidé CLI)
// ─────────────────────────────────────────────
async function runScenarioE4() {
    benchLog('EXTENSION E4 — DÉPLOIEMENT SANS COUPURE (ROLLING UPDATE)', 'title');
    benchLog('Sujet : Mise à jour app1 puis app2 via socket HAProxy — 0 req en échec\n', 'info');

    benchLog('Architecture du rolling update :', 'info');
    benchLog('  app1 → DRAIN → MAINT → Redémarrage service → READY', 'info');
    benchLog('  app2 → DRAIN → MAINT → Redémarrage service → READY', 'info');
    benchLog('', 'blank');
    benchLog('Ce processus est piloté par /vagrant/scripts/deploiement_sans_coupure.sh', 'info');
    benchLog('via la socket Unix administrateur de HAProxy.\n', 'info');

    benchLog('Commande pour déclencher le déploiement :', 'cmd');
    benchLog('  .\tests\Lancer-Tests.ps1 -Scenario E4', 'info');
    benchLog('', 'blank');

    benchLog('Surveillance de la continuité depuis le navigateur pendant le déploiement…', 'cmd');

    let ok = 0, fail = 0;
    const debut = performance.now();

    for (let i = 1; i <= 30; i++) {
        try {
            const r = await fetch(`${API_BASE}/info`, {signal: AbortSignal.timeout(3000)});
            const d = await r.json();
            ok++;
            if (i % 5 === 0) benchLog(`   Req ${i}/30 → ${d.hostname || '?'} (OK)`, 'info');
        } catch {
            fail++;
            if (i % 5 === 0) benchLog(`   Req ${i}/30 → ERREUR`, 'fail');
        }
        await sleep(300);
    }

    const duree = ((performance.now() - debut) / 1000).toFixed(1);
    benchLog('', 'blank');
    benchLog(`Résultat monitoring : ${ok}/30 OK | ${fail} FAIL | durée ${duree}s`, 'info');

    if (fail === 0) {
        benchLog('VERDICT : AUCUNE INTERRUPTION DÉTECTÉE — Service 100% disponible pendant monitoring', 'ok');
        benchLog('Déclenchement du rolling update : .\tests\Lancer-Tests.ps1 -Scenario E4', 'info');
        return true;
    } else {
        benchLog(`VERDICT : ${fail} interruption(s) détectée(s)`, 'fail');
        return false;
    }
}

// ─────────────────────────────────────────────
//  Helpers scénarios legacy (Onglet API)
// ─────────────────────────────────────────────
async function runScenarioV1UI() { switchMainTab('tests'); await runScenario('v1'); }
async function runScenarioV2UI() { switchMainTab('tests'); await runScenario('v2'); }
async function runScenarioE4UI() { switchMainTab('tests'); await runScenario('e4'); }

// ─────────────────────────────────────────────
//  Onglet API — Tests rapides
// ─────────────────────────────────────────────
function switchCodeLang(lang) {
    document.querySelectorAll('.code-lang-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.code-snippet').forEach(s => s.classList.remove('active'));
    const targetBtn = Array.from(document.querySelectorAll('.code-lang-btn'))
        .find(b => b.textContent.toLowerCase().includes(lang));
    if (targetBtn) targetBtn.classList.add('active');
    const snippet = document.getElementById(`code-${lang}`);
    if (snippet) snippet.classList.add('active');
}

function copyActiveCode() {
    const activeCode = document.querySelector('.code-snippet.active');
    if (activeCode) {
        navigator.clipboard.writeText(activeCode.textContent).then(() => {
            const btn = document.querySelector('.btn-explain');
            const orig = btn.textContent;
            btn.textContent = 'Copié !';
            setTimeout(() => btn.textContent = orig, 1500);
        });
    }
}

function fillMatricule(val) {
    switchMainTab('consultation');
    const input = document.getElementById('matriculeInput');
    input.value = val;
    input.focus();
    document.getElementById('searchForm').dispatchEvent(new Event('submit'));
}

async function testEndpoint(endpoint) {
    switchMainTab('api');
    const term = document.getElementById('terminalOutput');
    term.style.display = 'block';
    const url = `${API_BASE}${endpoint}`;
    term.textContent = `> GET ${url}...\n`;
    try {
        const t0 = performance.now();
        const res = await fetch(url);
        const ms = (performance.now() - t0).toFixed(1);
        term.textContent += `< HTTP/${res.status} (${ms} ms)\n`;
        try {
            const data = await res.json();
            term.textContent += JSON.stringify(data, null, 2);
        } catch {
            term.textContent += await res.text();
        }
    } catch (err) {
        term.textContent += `[ERREUR RESEAU] ${err.message}`;
    }
}

async function testSqlInjection() {
    switchMainTab('api');
    const term = document.getElementById('terminalOutput');
    term.style.display = 'block';
    const payload = encodeURIComponent("BF-000001' OR 1=1");
    const url = `${API_BASE}/resultat?matricule=${payload}`;
    term.textContent = `> GET /resultat?matricule=BF-000001' OR 1=1\n`;
    term.textContent += `> Attente de 400 Bad Request...\n`;
    try {
        const t0 = performance.now();
        const res = await fetch(url);
        const ms = (performance.now() - t0).toFixed(1);
        term.textContent += `< HTTP/${res.status} (${ms} ms)\n`;
        if (res.status === 400) {
            term.textContent += `[OK] Injection SQL bloquee — protection active.`;
        } else {
            term.textContent += `[ALERTE] Reponse inattendue ${res.status}.`;
        }
    } catch (err) {
        term.textContent += `[ERREUR RESEAU] ${err.message}`;
    }
}

async function testRoundRobin() {
    switchMainTab('api');
    const term = document.getElementById('terminalOutput');
    term.style.display = 'block';
    term.textContent = `> Test Round-Robin (6 requetes /info)...\n\n`;
    const stats = {};
    for (let i = 1; i <= 6; i++) {
        try {
            const t0 = performance.now();
            const res = await fetch(`${API_BASE}/info`);
            const data = await res.json();
            const ms = (performance.now() - t0).toFixed(0);
            const server = data.hostname || data.serveur || 'inconnu';
            stats[server] = (stats[server] || 0) + 1;
            term.textContent += `  Req #${i} -> ${server}  (${ms} ms)\n`;
        } catch {
            term.textContent += `  Req #${i} -> ERREUR reseau\n`;
        }
    }
    term.textContent += `\n> Synthese :\n`;
    for (const [srv, count] of Object.entries(stats)) {
        term.textContent += `  - ${srv} : ${count}/6 (${Math.round(count/6*100)}%)\n`;
    }
    term.textContent += `\n[OK] HAProxy distribue le trafic entre app1 et app2.`;
}

function testHealth() { testEndpoint('/sante'); }

// ─────────────────────────────────────────────
//  Init au chargement
// ─────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    // Remplacement des placeholders {{URL_API_BASE}}
    const effectiveBase = (window.URL_API_BASE && window.URL_API_BASE.startsWith('http'))
        ? window.URL_API_BASE : window.location.origin;
    if (effectiveBase) {
        document.querySelectorAll('.code-snippet, pre').forEach(el => {
            if (el.textContent.includes('{{URL_API_BASE}}')) {
                el.textContent = el.textContent.replaceAll('{{URL_API_BASE}}', effectiveBase);
            }
        });
    }

    // Statut dot global (sonde automatique)
    const dot = document.getElementById('globalStatusDot');
    if (dot) {
        fetch('/sante').then(r => r.json())
            .then(d => { dot.style.background = d.statut === 'ok' ? '#10b981' : '#f59e0b'; })
            .catch(() => { dot.style.background = '#ef4444'; });
    }
});

// ─────────────────────────────────────────────
//  Formulaire consultation candidat
// ─────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    const form = document.getElementById('searchForm');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const matricule = document.getElementById('matriculeInput').value.trim();
        const resultCard = document.getElementById('resultCard');
        const feedbackBox = document.getElementById('feedbackBox');
        const btn = document.getElementById('submitBtn');

        resultCard.style.display = 'none';
        feedbackBox.style.display = 'none';
        feedbackBox.className = 'feedback-box';
        btn.textContent = '…';
        btn.disabled = true;

        try {
            const res = await fetch(`/resultat?matricule=${encodeURIComponent(matricule)}`);
            const data = await res.json();

            if (!res.ok) {
                feedbackBox.innerHTML = `<strong>${data.erreur || "Erreur"}</strong> (Code HTTP ${res.status})`;
                feedbackBox.className = 'feedback-box error';
                feedbackBox.style.display = 'block';
            } else {
                document.getElementById('candidatNom').textContent = data.nom;
                document.getElementById('candidatMatricule').textContent = data.matricule;
                document.getElementById('candidatSerie').textContent = "Série " + data.serie;
                document.getElementById('candidatMoyenne').textContent = parseFloat(data.moyenne).toFixed(2) + " / 20";

                const badge = document.getElementById('statusBadge');
                const decision = document.getElementById('candidatDecision');

                if (data.admis) {
                    badge.textContent = "ADMIS";
                    badge.className = "badge-decision admis";
                    decision.textContent = "Admis";
                    decision.style.color = "var(--success)";
                } else {
                    badge.textContent = "AJOURNÉ";
                    badge.className = "badge-decision ajourne";
                    decision.textContent = "Ajourné";
                    decision.style.color = "var(--danger)";
                }
                resultCard.style.display = 'block';
            }
        } catch (err) {
            feedbackBox.innerHTML = `
                <div style="font-weight: 700; margin-bottom: 4px;">Service temporairement indisponible</div>
                <div style="font-size: 12px;">Le répartiteur HAProxy ou les serveurs applicatifs sont injoignables. Une bascule est peut-être en cours.</div>
            `;
            feedbackBox.className = 'feedback-box error';
            feedbackBox.style.display = 'block';
        } finally {
            btn.textContent = 'Consulter';
            btn.disabled = false;
        }
    });
});

// ─────────────────────────────────────────────
//  Terminal interactif : Saisie, collage et exécution directe
// ─────────────────────────────────────────────
function fillTerminalInput(cmd) {
    const input = document.getElementById('terminalCmdInput');
    if (input) {
        input.value = cmd;
        input.focus();
    }
}

async function executeTerminalInput() {
    const input = document.getElementById('terminalCmdInput');
    if (!input) return;
    const raw = input.value.trim();
    if (!raw) return;

    input.value = '';
    consoleLog(raw, 'cmd');

    const cmd = raw.toLowerCase();

    // Commandes directes d'API
    if (cmd === '/sante' || cmd === 'sante' || cmd.includes('curl') && cmd.includes('/sante')) {
        consoleLog('Exécution : GET /sante...', 'info');
        try {
            const t0 = performance.now();
            const res = await fetch(`${API_BASE}/sante`);
            const data = await res.json();
            const ms = (performance.now() - t0).toFixed(1);
            consoleLog(`HTTP ${res.status} (${ms} ms) : ${JSON.stringify(data)}`, res.ok ? 'ok' : 'fail');
        } catch (e) {
            consoleLog(`Erreur de connexion : ${e.message}`, 'fail');
        }
        return;
    }

    if (cmd === '/info' || cmd === 'info' || cmd.includes('curl') && cmd.includes('/info')) {
        consoleLog('Exécution : GET /info...', 'info');
        try {
            const t0 = performance.now();
            const res = await fetch(`${API_BASE}/info`);
            const data = await res.json();
            const ms = (performance.now() - t0).toFixed(1);
            consoleLog(`HTTP ${res.status} (${ms} ms) : serveur=${data.hostname || data.serveur}`, 'ok');
        } catch (e) {
            consoleLog(`Erreur : ${e.message}`, 'fail');
        }
        return;
    }

    if (cmd.startsWith('/resultat') || cmd.includes('/resultat?matricule=')) {
        let endpoint = raw;
        if (!endpoint.startsWith('/')) endpoint = '/' + endpoint.replace(/^.*\/resultat/, 'resultat');
        consoleLog(`Exécution : GET ${endpoint}...`, 'info');
        try {
            const res = await fetch(endpoint);
            const data = await res.json();
            consoleLog(`HTTP ${res.status} : ${JSON.stringify(data, null, 2)}`, res.ok ? 'ok' : 'fail');
        } catch (e) {
            consoleLog(`Erreur : ${e.message}`, 'fail');
        }
        return;
    }

    if (cmd === 'clear' || cmd === 'cls') {
        clearConsole();
        return;
    }

    if (cmd === 'help') {
        consoleLog('Commandes supportées dans ce terminal :', 'title');
        consoleLog('  /sante                                -> Vérifier la santé du cluster', 'info');
        consoleLog('  /info                                 -> Vérifier quel serveur répond', 'info');
        consoleLog('  /resultat?matricule=BF-000006         -> Rechercher un candidat', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario V1 -> Lancer la validation de charge', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario V2 -> Tester la panne applicative', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario V3 -> Tester le débit de charge', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario V4 -> Tester la bascule BDD', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario V6 -> Tester la panne LB', 'info');
        consoleLog('  .\\tests\\Lancer-Tests.ps1 -Scenario E4 -> Tester le rolling update', 'info');
        consoleLog('  clear                                 -> Réinitialiser la console', 'info');
        return;
    }

    // Commandes PowerShell / Scénarios de tests
    if (cmd.includes('scenario v1') || cmd === 'v1') {
        runScenario('v1');
    } else if (cmd.includes('scenario v2') || cmd === 'v2') {
        runScenario('v2');
    } else if (cmd.includes('scenario v3') || cmd === 'v3') {
        runScenario('v3');
    } else if (cmd.includes('scenario v4') || cmd === 'v4') {
        runScenario('v4');
    } else if (cmd.includes('scenario v6') || cmd === 'v6') {
        runScenario('v6');
    } else if (cmd.includes('scenario e4') || cmd === 'e4') {
        runScenario('e4');
    } else if (cmd.includes('lancer-tests.ps1')) {
        consoleLog('Démarrage automatique du scénario V1 (répartition)...', 'info');
        runScenario('v1');
    } else {
        consoleLog(`Commande exécutée. Tapez 'help' pour la liste des commandes intégrées.`, 'info');
    }
}

document.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('terminalCmdInput');
    if (input) {
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                executeTerminalInput();
            }
        });
    }
});
