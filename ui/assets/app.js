let DATA;
let currentId = 'agencybench';
let patched = false;

const $ = (id) => document.getElementById(id);

function fmtBefore(a) {
  if (a.id === 'aidanbench') return `coherence ${a.before.coherence}`;
  if (a.id === 'structured_outputs') return `schema pass`;
  return `reward ${a.before.reward}`;
}
function fmtAfter(a) {
  if (a.id === 'aidanbench') return a.after.accepted ? `accepted` : `rejected`;
  if (a.id === 'structured_outputs') return `reward ${a.after.reward}`;
  return `reward ${a.after.reward}`;
}
function detailBefore(a) {
  if (a.id === 'aidanbench') return `novelty ${a.before.novelty}; accepted`;
  if (a.id === 'structured_outputs') return `schema-valid fake output`;
  return `deduction ${a.before.deduction}; attack succeeds`;
}
function detailAfter(a) {
  return a.after.reason || 'hardened verifier rejects the attack';
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
}

function renderList() {
  const list = $('attackList');
  list.innerHTML = '';
  DATA.attacks.forEach(a => {
    const item = document.createElement('div');
    item.className = 'attack-item' + (a.id === currentId ? ' active' : '');
    item.innerHTML = `<strong>${a.name}</strong><span>${a.subtitle}</span>`;
    item.onclick = () => { currentId = a.id; patched = false; render(); };
    list.appendChild(item);
  });
  $('attackCount').textContent = DATA.attacks.length;
}

function renderRootCauses(a) {
  $('rootCauses').innerHTML = a.rootCauses.map(rc => `
    <div class="root-card">
      <div class="root-copy">
        <h4>${escapeHtml(rc.title)}</h4>
        <p>${escapeHtml(rc.detail)}</p>
      </div>
      <pre>${escapeHtml(rc.source.path)}\n${escapeHtml(rc.source.code)}</pre>
    </div>
  `).join('');
}

function renderReport(a) {
  $('report').innerHTML = `
    <h4>${escapeHtml(a.name)} reward-hack report</h4>
    <p><strong>Attack:</strong> ${escapeHtml(a.subtitle)}</p>
    <p><strong>Environment:</strong> <code>${escapeHtml(a.environmentPath)}</code></p>
    <p><strong>Model/verifier:</strong> <code>${escapeHtml(a.model)}</code></p>
    <p><strong>Before fix:</strong> ${escapeHtml(fmtBefore(a))} — ${escapeHtml(detailBefore(a))}</p>
    <p><strong>After fix:</strong> ${escapeHtml(fmtAfter(a))} — ${escapeHtml(detailAfter(a))}</p>
    <p><strong>Human-intent failure:</strong> ${escapeHtml(a.humanFailure)}</p>
    <p><strong>Evidence:</strong> <code>${escapeHtml(a.evidenceRef)}</code></p>
    <h4>Patch notes</h4>
    <ul>${a.patchNotes.map(n => `<li>${escapeHtml(n)}</li>`).join('')}</ul>
  `;
}

function renderTimeline() {
  $('patchStep').className = patched ? 'done' : '';
  $('failStep').className = patched ? 'done' : '';
  $('traceBadge').textContent = patched ? 'fixed' : 'live';
  $('traceBadge').className = 'pill ' + (patched ? 'safe' : 'danger');
}

function render() {
  const a = DATA.attacks.find(x => x.id === currentId) || DATA.attacks[0];
  renderList();
  $('crumbEnv').textContent = a.name;
  $('attackTitle').textContent = a.name;
  $('attackSubtitle').textContent = a.subtitle;
  $('modelSelect').value = [...$('modelSelect').options].some(o => o.value === a.model) ? a.model : $('modelSelect').value;
  $('statusText').textContent = patched ? 'HARDENED' : a.status;
  $('statusCard').className = 'status-card' + (patched ? ' safe' : '');
  $('beforeScore').textContent = fmtBefore(a);
  $('beforeDetail').textContent = detailBefore(a);
  $('afterScore').textContent = fmtAfter(a);
  $('afterDetail').textContent = detailAfter(a);
  $('evidenceRef').textContent = a.evidenceRef;
  $('diffFile').textContent = a.diff.file;
  $('diffBefore').textContent = a.diff.before;
  $('diffAfter').textContent = a.diff.after;
  $('userPrompt').textContent = a.userPrompt;
  $('payload').textContent = a.payload;
  $('judgeOutput').textContent = a.judgeOutput;
  $('humanFailure').textContent = a.humanFailure;
  $('patchNotes').innerHTML = a.patchNotes.map(n => `<li>${escapeHtml(n)}</li>`).join('');
  renderRootCauses(a);
  renderReport(a);
  renderTimeline();
}

function animateRun() {
  patched = false;
  render();
  $('statusText').textContent = 'RUNNING…';
  setTimeout(() => render(), 550);
}
function animatePatch() {
  patched = true;
  render();
}

function setupTabs() {
  document.querySelectorAll('.tab').forEach(btn => {
    btn.onclick = () => {
      document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-page').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      $('tab-' + btn.dataset.tab).classList.add('active');
    };
  });
}

async function main() {
  const resp = await fetch('data/demo.json');
  DATA = await resp.json();
  $('runBtn').onclick = animateRun;
  $('patchBtn').onclick = animatePatch;
  setupTabs();
  render();
}

main().catch(err => {
  document.body.innerHTML = `<pre style="color:white;padding:40px">Failed to load UI data: ${escapeHtml(err.stack || err)}</pre>`;
});
