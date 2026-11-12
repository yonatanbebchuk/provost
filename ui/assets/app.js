let attacks = [];
let currentId = 'agencybench';
let currentAttack = null;
let patched = false;
let revealed = false;
let running = false;
let verifying = false;
let lastRun = null;

const $ = (id) => document.getElementById(id);
const fmtReward = (r) => `reward ${Number(r).toFixed(1)}`;
/** Where the environment lives, e.g. primeintellect/agency_bench — shown instead of the attack name. */
const envSource = (a) => String(a.environmentPath || 'registered').replace(/^environments\//, '').replace(/\.py$/, '');
const escapeHtml = (s) => String(s ?? '').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

async function api(path, options) {
  const resp = await fetch(path, options);
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(data.error || `${path} failed: ${resp.status}`);
  return data;
}

function fmtBefore(a) {
  if (a.id === 'aidanbench') return `coherence ${a.before.coherence}`;
  if (a.id === 'structured_outputs') return 'schema pass';
  return fmtReward(a.before.reward);
}
function fmtAfter(a) {
  if (a.id === 'aidanbench') return a.after.accepted ? 'accepted' : 'rejected';
  return fmtReward(a.after.reward);
}
function detailBefore(a) {
  if (a.id === 'aidanbench') return `novelty ${a.before.novelty}; accepted by the reward gates`;
  if (a.id === 'structured_outputs') return 'valid JSON structure, but fabricated content';
  return `deduction ${a.before.deduction}; attack succeeds`;
}
function detailAfter(a) { return a.after.reason || 'hardened verifier rejects the attack'; }

function renderList() {
  const list = $('attackList');
  list.innerHTML = '';
  attacks.forEach(a => {
    const item = document.createElement('div');
    item.className = 'attack-item' + (a.id === currentId ? ' active' : '');
    item.innerHTML = `<strong>${escapeHtml(a.name)}</strong><span>${escapeHtml(envSource(a))}</span>`;
    item.onclick = async () => { currentId = a.id; resetRun(); await loadAttack(); };
    list.appendChild(item);
  });
}

function renderRootCauses(a) {
  $('rootCauses').innerHTML = a.rootCauses.map((rc, i) => `
    <div class="root-card">
      <div class="root-copy">
        <h4>${i + 1}. ${escapeHtml(rc.title)}</h4>
        <p>${escapeHtml(rc.detail)}</p>
      </div>
      <pre>${escapeHtml(rc.source.path)}\n${escapeHtml(rc.source.code)}</pre>
    </div>
  `).join('');
}

function render() {
  const a = currentAttack;
  if (!a) return;
  renderList();

  $('attackTitle').textContent = a.name;
  $('attackSubtitle').textContent = revealed ? a.subtitle : '';
  $('revealed').hidden = !revealed;
  $('runPanel').hidden = revealed;
  $('patchBtn').disabled = !revealed || running || verifying;
  $('modelSelect').value = [...$('modelSelect').options].some(o => o.value === a.model) ? a.model : $('modelSelect').value;

  renderStatus();

  $('environmentDefinition').textContent = a.environmentDefinition;
  $('rewardRule').textContent = a.rewardRule;
  $('humanIntent').textContent = a.humanIntent;
  $('attackExplanation').textContent = a.attackExplanation;

  $('userPrompt').textContent = a.userPrompt;
  $('payload').textContent = a.payload;
  $('judgeOutput').textContent = a.judgeOutput;
  if (!$('harnessTrace').dataset.loadedFor || $('harnessTrace').dataset.loadedFor !== a.id) {
    $('harnessTrace').textContent = 'Click “Run attack” to execute the local harness.';
  }
  $('humanFailure').textContent = a.humanFailure;

  $('beforeScore').textContent = fmtBefore(a);
  $('beforeDetail').textContent = detailBefore(a);
  $('afterScore').textContent = fmtAfter(a);
  $('afterDetail').textContent = detailAfter(a);

  renderRootCauses(a);
  $('diffBefore').textContent = a.diff.before;
  $('diffAfter').textContent = a.diff.after;
  $('patchNotes').innerHTML = a.patchNotes.map(n => `<li>${escapeHtml(n)}</li>`).join('');
}

async function loadAttack() {
  currentAttack = await api(`/api/attacks/${encodeURIComponent(currentId)}`);
  render();
}

async function refreshAttackList() {
  const summary = await api('/api/attacks');
  attacks = summary.attacks;
}

async function registerAttack(event) {
  event.preventDefault();
  const status = $('registerStatus');
  status.className = 'register-status';
  status.textContent = 'Saving...';
  const form = event.currentTarget;
  const payload = Object.fromEntries(new FormData(form).entries());
  if (payload.beforeReward) payload.beforeReward = Number(payload.beforeReward);
  if (payload.afterReward) payload.afterReward = Number(payload.afterReward);
  try {
    const result = await api('/api/attacks', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(payload),
    });
    status.className = 'register-status ok';
    status.textContent = `Saved ${result.attack.id}`;
    currentId = result.attack.id;
    resetRun();
    await refreshAttackList();
    await loadAttack();
    form.reset();
  } catch (err) {
    status.className = 'register-status err';
    status.textContent = err.message;
  }
}

function resetRun() {
  patched = false; revealed = false; lastRun = null;
  $('harnessTrace').dataset.loadedFor = '';
  $('verifyTitle').textContent = 'Verify the fix';
  $('verifyDetail').textContent = 'Re-runs the same attack against the hardened verifier.';
  $('verifyBtn').textContent = 'Verify fix';
}

function renderStatus() {
  let text = 'Not run', cls = '';
  if (running) text = 'Running harness';
  else if (verifying) text = 'Verifying fix';
  else if (patched && lastRun) { text = lastRun.fixed ? 'Fixed' : 'Fix failed'; cls = lastRun.fixed ? 'fixed' : 'vulnerable'; }
  else if (revealed && lastRun) { text = lastRun.vulnerable ? 'Attack succeeded' : 'Not vulnerable'; cls = lastRun.vulnerable ? 'vulnerable' : 'fixed'; }
  $('statusBadge').textContent = text;
  $('statusBadge').className = 'status ' + cls;
}

/** Swap a button's label for a spinner while `busy`. */
function setBusy(btn, busy, busyLabel) {
  if (busy) {
    btn.dataset.label = btn.textContent;
    btn.innerHTML = `<span class="spinner"></span>${escapeHtml(busyLabel)}`;
  } else if (btn.dataset.label) {
    btn.textContent = btn.dataset.label;
  }
  btn.disabled = busy;
}

async function runAttack() {
  if (running || verifying) return;
  running = true; patched = false;
  const buttons = [$('runBtn'), $('runBtnInline')];
  buttons.forEach(b => setBusy(b, true, 'Running…'));
  $('runTitle').textContent = 'Running the harness…';
  renderStatus();
  try {
    const result = await api(`/api/harness/run/${encodeURIComponent(currentId)}`);
    lastRun = result;
    revealed = true;
    $('harnessTrace').dataset.loadedFor = currentId;
    $('harnessTrace').textContent = result.steps.map(s => `[${s.status}] ${s.name}: ${s.detail}`).join('\n') + `\n\nreward_before=${result.reward_before}\nreward_after=${result.reward_after}\nvulnerable=${result.vulnerable}\nfixed=${result.fixed}`;
  } catch (err) {
    $('runTitle').textContent = `Harness error: ${err.message}`;
  } finally {
    running = false;
    buttons.forEach(b => setBusy(b, false));
    if ($('runTitle').textContent === 'Running the harness…') $('runTitle').textContent = 'Ready to run';
    render();
    if (lastRun) {
      $('beforeScore').textContent = fmtReward(lastRun.reward_before);
      $('afterScore').textContent = fmtReward(lastRun.reward_after);
    }
  }
}

async function verifyFix() {
  if (!revealed || running || verifying) return;
  verifying = true;
  const buttons = [$('verifyBtn'), $('patchBtn')];
  buttons.forEach(b => setBusy(b, true, 'Verifying…'));
  renderStatus();
  try {
    const result = await api(`/api/harness/run/${encodeURIComponent(currentId)}`);
    lastRun = result;
    patched = true;
    $('verifyTitle').textContent = result.fixed ? 'Fix verified' : 'Fix did not hold';
    $('verifyTitle').className = result.fixed ? 'ok' : 'err';
    $('verifyDetail').textContent = `Re-ran the same attack. Vulnerable reward ${Number(result.reward_before).toFixed(1)} → hardened reward ${Number(result.reward_after).toFixed(1)}.`;
  } catch (err) {
    $('verifyDetail').textContent = err.message;
  } finally {
    verifying = false;
    buttons.forEach(b => setBusy(b, false));
    $('verifyBtn').textContent = patched ? 'Run again' : 'Verify fix';
    render();
    if (lastRun) {
      $('beforeScore').textContent = fmtReward(lastRun.reward_before);
      $('afterScore').textContent = fmtReward(lastRun.reward_after);
    }
  }
}

async function main() {
  await refreshAttackList();
  if (!attacks.find(a => a.id === currentId) && attacks[0]) currentId = attacks[0].id;
  $('runBtn').onclick = runAttack;
  $('runBtnInline').onclick = runAttack;
  $('patchBtn').onclick = verifyFix;
  $('verifyBtn').onclick = verifyFix;
  $('registerForm').onsubmit = registerAttack;
  await loadAttack();
}

main().catch(err => {
  document.body.innerHTML = `<pre style="color:white;padding:40px">Failed to load UI data from backend.\n\nRun:\n  python3 scripts/reward_hack_server.py --port 8765\n\n${escapeHtml(err.stack || err)}</pre>`;
});
