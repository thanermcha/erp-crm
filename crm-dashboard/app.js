/* ── GrowERP CRM Dashboard — App Logic ── */

document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  renderOverview();
  renderPersonas();
  renderLandingPages();
  renderCampaigns();
  renderMessages();
  initAnalytics();
  renderAnalytics('last16months');
  renderObservability();
});

// ═══════════ TAB NAVIGATION ═══════════
function initTabs() {
  const tabs = document.querySelectorAll('.nav-tab');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
      tab.classList.add('active');
      const target = document.getElementById('panel-' + tab.dataset.panel);
      if (target) {
        target.classList.add('active');
        target.style.animation = 'none';
        void target.offsetWidth;
        target.style.animation = 'fadeSlideIn .4s ease';
      }
    });
  });
}

// ═══════════ OVERVIEW ═══════════
function renderOverview() {
  const map = document.getElementById('segment-map');
  const segments = [
    { key: 'agro',       sub: 'agronegocio.blahsoftware.ia.br' },
    { key: 'agents',     sub: 'agents.blahsoftware.com.br' },
    { key: 'enterprise', sub: 'enterprise.blahsoftware.ia.br' },
    { key: 'business',   sub: 'business.blahsoftware.ia.br' },
    { key: 'franquia',   sub: 'franquia.blahsoftware.ia.br' },
    { key: 'solucoes',   sub: 'solucoes.blahsoftware.ia.br' },
  ];
  segments.forEach(s => {
    const c = SEGMENT_COLORS[s.key];
    const el = document.createElement('div');
    el.className = 'seg-chip';
    el.style.setProperty('--seg-accent', c.accent);
    el.style.setProperty('--seg-bg', c.bg);
    el.innerHTML = `
      <span class="seg-tag">${c.tag}</span>
      <span class="seg-name">${s.key.charAt(0).toUpperCase() + s.key.slice(1)}</span>
      <span class="seg-url">${s.sub}</span>
    `;
    map.appendChild(el);
  });
}

// ═══════════ PERSONAS ═══════════
function renderPersonas() {
  const grid = document.getElementById('personas-grid');
  PERSONAS.forEach(p => {
    const c = SEGMENT_COLORS[p.segment];
    const card = document.createElement('div');
    card.className = 'persona-card';
    card.style.setProperty('--seg-accent', c.accent);
    card.style.setProperty('--seg-bg', c.bg);
    card.innerHTML = `
      <div class="persona-header">
        <span class="persona-tag">${c.tag}</span>
        <h3>${p.name}</h3>
        <span class="persona-segment">${p.segment}</span>
      </div>
      <div class="persona-body">
        <div class="persona-field">
          <label>Demográfico</label>
          <p>${p.demographics}</p>
        </div>
        <div class="persona-field">
          <label>Dores</label>
          <p>${p.painPoints}</p>
        </div>
        <div class="persona-field">
          <label>Objetivos</label>
          <p>${p.goals}</p>
        </div>
        <div class="persona-field">
          <label>Tom de Voz</label>
          <p class="tone">${p.tone}</p>
        </div>
      </div>
    `;
    grid.appendChild(card);
  });
}

// ═══════════ LANDING PAGES ═══════════
function renderLandingPages() {
  const grid = document.getElementById('lp-grid');
  LANDING_PAGES.forEach(lp => {
    const c = SEGMENT_COLORS[lp.segment];
    const el = document.createElement('div');
    el.className = 'lp-card';
    el.style.setProperty('--seg-accent', c.accent);
    el.style.setProperty('--seg-bg', c.bg);
    el.innerHTML = `
      <div class="lp-top" style="background: linear-gradient(135deg, ${c.bg}, ${c.accent}22);">
        <span class="lp-tag">${c.tag}</span>
        <span class="lp-status ${lp.status.toLowerCase()}">${lp.status}</span>
        <h3>${lp.title}</h3>
        <p class="lp-headline">${lp.headline}</p>
      </div>
      <div class="lp-body">
        <p class="lp-sub">${lp.subheading}</p>
        <div class="lp-url-row">
          <span class="lp-url-label">URL</span>
          <a href="${lp.url}" target="_blank" class="lp-url">${lp.url}</a>
        </div>
        <div class="lp-sections">
          <h4>Seções</h4>
          ${lp.sections.map(s => `
            <div class="lp-sec">
              <strong>${s.title}</strong>
              <p>${s.desc}</p>
            </div>
          `).join('')}
        </div>
        <div class="lp-cred">
          <h4>Credibilidade</h4>
          <p>${lp.credibility}</p>
          <ul>${lp.stats.map(s => `<li>${s}</li>`).join('')}</ul>
        </div>
      </div>
    `;
    grid.appendChild(el);
  });
}

// ═══════════ CAMPAIGNS ═══════════
function renderCampaigns() {
  const tbody = document.getElementById('campaign-tbody');
  CAMPAIGNS.forEach(camp => {
    const c = SEGMENT_COLORS[camp.segment];
    const lp = LANDING_PAGES.find(l => l.id === camp.landingPage);
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><span class="camp-name" style="border-left:3px solid ${c.accent}; padding-left:8px;">${camp.name}</span></td>
      <td><span class="seg-badge" style="background:${c.accent}20; color:${c.accent};">${c.tag} ${camp.segment}</span></td>
      <td>${camp.platforms.map(p => `<span class="platform-chip ${p.toLowerCase()}">${p === 'WHATSAPP' ? '📱' : '📧'} ${p}</span>`).join(' ')}</td>
      <td class="audience-cell">${camp.audience}</td>
      <td><span class="status-badge planned">${camp.status}</span></td>
      <td class="num-cell">${camp.dailyLimit}/dia</td>
      <td><a href="${lp ? lp.url : '#'}" target="_blank" class="lp-link">${lp ? lp.url.replace('https://','') : '—'}</a></td>
    `;
    tbody.appendChild(tr);
  });
}

// ═══════════ MESSAGES ═══════════
function renderMessages(channelFilter) {
  const grid = document.getElementById('msg-grid');
  grid.innerHTML = '';
  const filter = channelFilter || 'all';

  CAMPAIGNS.forEach(camp => {
    const c = SEGMENT_COLORS[camp.segment];

    if (filter === 'all' || filter === 'whatsapp') {
      const wa = document.createElement('div');
      wa.className = 'msg-card whatsapp';
      wa.style.setProperty('--seg-accent', c.accent);
      wa.innerHTML = `
        <div class="msg-top">
          <span class="msg-channel-icon">📱</span>
          <span class="msg-channel-name">WhatsApp</span>
          <span class="msg-seg">${c.tag} ${camp.segment}</span>
        </div>
        <div class="msg-body">
          <div class="msg-bubble wa-bubble">
            <p>${camp.whatsappMsg}</p>
          </div>
          <div class="msg-meta">
            <span class="meta-label">Mensagem curta:</span>
            <span class="meta-value">${camp.whatsappShort}</span>
          </div>
        </div>
      `;
      grid.appendChild(wa);
    }

    if (filter === 'all' || filter === 'email') {
      const em = document.createElement('div');
      em.className = 'msg-card email';
      em.style.setProperty('--seg-accent', c.accent);
      em.innerHTML = `
        <div class="msg-top">
          <span class="msg-channel-icon">📧</span>
          <span class="msg-channel-name">Email</span>
          <span class="msg-seg">${c.tag} ${camp.segment}</span>
        </div>
        <div class="msg-body">
          <div class="msg-subject">
            <span class="meta-label">Assunto:</span>
            <span class="meta-value">${camp.emailSubject}</span>
          </div>
          <div class="msg-bubble em-bubble">
            <p>${camp.whatsappMsg}</p>
          </div>
          <div class="msg-meta">
            <span class="meta-label">CTA Link:</span>
            <a href="${camp.emailCta}" target="_blank" class="meta-link">${camp.emailCta}</a>
          </div>
        </div>
      `;
      grid.appendChild(em);
    }
  });
}

// Message filter buttons
document.addEventListener('click', (e) => {
  if (e.target.classList.contains('msg-filter')) {
    document.querySelectorAll('.msg-filter').forEach(b => b.classList.remove('active'));
    e.target.classList.add('active');
    renderMessages(e.target.dataset.channel);
  }
});

// ═══════════ SEARCH CONSOLE ANALYTICS ═══════════
let currentRange = 'last16months';

function initAnalytics() {
  const rangeBtns = document.querySelectorAll('.range-btn');
  rangeBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      rangeBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentRange = btn.dataset.range;
      renderAnalytics(currentRange);
    });
  });
}

function renderAnalytics(range) {
  const store = VN_MAQUINAS_ANALYTICS[range];
  if (!store) return;

  const formatNum = (num) => num.toLocaleString('pt-BR');

  // 1. Update KPIs
  document.getElementById('val-clicks').textContent = formatNum(store.summary.clicks);
  document.getElementById('val-impressions').textContent = formatNum(store.summary.impressions);
  document.getElementById('val-ctr').textContent = store.summary.ctr.toFixed(1) + '%';
  document.getElementById('val-position').textContent = store.summary.position.toFixed(1);

  // 2. Populate Queries Table
  const qBody = document.getElementById('table-queries-body');
  qBody.innerHTML = '';
  store.data.queries.slice(0, 10).forEach(q => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><strong>${q.query}</strong></td>
      <td>${formatNum(q.clicks)}</td>
      <td>${formatNum(q.impressions)}</td>
      <td>${q.ctr.toFixed(1)}%</td>
      <td>${q.position.toFixed(1)}</td>
    `;
    qBody.appendChild(tr);
  });

  // 3. Populate Pages Table
  const pBody = document.getElementById('table-pages-body');
  pBody.innerHTML = '';
  store.data.pages.slice(0, 10).forEach(p => {
    const tr = document.createElement('tr');
    const displayPage = p.page.replace('https://vnmaquinas.com.br/', '/');
    tr.innerHTML = `
      <td><a href="${p.page}" target="_blank" style="color: var(--accent-secondary); text-decoration: none;" title="${p.page}">${displayPage === '/' ? 'Home (/)' : displayPage}</a></td>
      <td>${formatNum(p.clicks)}</td>
      <td>${formatNum(p.impressions)}</td>
      <td>${p.ctr.toFixed(1)}%</td>
      <td>${p.position.toFixed(1)}</td>
    `;
    pBody.appendChild(tr);
  });

  // 4. Populate Countries Table
  const cBody = document.getElementById('table-countries-body');
  cBody.innerHTML = '';
  store.data.countries.slice(0, 5).forEach(c => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${c.country}</td>
      <td>${formatNum(c.clicks)}</td>
      <td>${formatNum(c.impressions)}</td>
      <td>${c.ctr.toFixed(1)}%</td>
      <td>${c.position.toFixed(1)}</td>
    `;
    cBody.appendChild(tr);
  });

  // 5. Populate Devices Breakdown
  const dList = document.getElementById('device-list');
  dList.innerHTML = '';
  const totalDevImpressions = store.data.devices.reduce((acc, d) => acc + d.impressions, 0);
  store.data.devices.forEach(d => {
    const pct = totalDevImpressions > 0 ? ((d.impressions / totalDevImpressions) * 100).toFixed(1) : 0;
    const div = document.createElement('div');
    div.className = 'device-item';
    div.innerHTML = `
      <div class="device-meta">
        <span class="device-name">${d.device === 'Computador' ? '💻 Computador' : d.device === 'Celular' ? '📱 Celular' : '📟 Tablet'}</span>
        <span class="device-pct">${pct}% (${formatNum(d.clicks)} cliques)</span>
      </div>
      <div class="device-bar-outer">
        <div class="device-bar-inner" style="width: ${pct}%"></div>
      </div>
    `;
    dList.appendChild(div);
  });
}

// ═══════════ OBSERVABILITY ═══════════
function renderObservability() {
  // 1. Render Infra Stats
  const infraGrid = document.getElementById('infra-stats-grid');
  infraGrid.innerHTML = '';
  
  const infraMapping = [
    { key: 'vpn', icon: '🔒', label: 'VPN Status', val: OBSERVABILITY_DATA.infra.vpn.status, sub: OBSERVABILITY_DATA.infra.vpn.latency, color: 'purple' },
    { key: 'ssh', icon: '🔑', label: 'SSH Access', val: OBSERVABILITY_DATA.infra.ssh.status, sub: \`\${OBSERVABILITY_DATA.infra.ssh.activeConnections} ativos\`, color: 'blue' },
    { key: 'network', icon: '📡', label: 'Network', val: OBSERVABILITY_DATA.infra.network.status, sub: OBSERVABILITY_DATA.infra.network.throughput, color: 'teal' },
  ];

  infraMapping.forEach(item => {
    const card = document.createElement('div');
    card.className = \`stat-card \${item.color}\`;
    card.innerHTML = \`
      <div class="stat-icon">\${item.icon}</div>
      <div class="stat-value">\${item.val}</div>
      <div class="stat-label">\${item.label}</div>
      <div style="font-size: 0.85rem; opacity: 0.8; margin-top: 4px;">\${item.sub}</div>
    \`;
    infraGrid.appendChild(card);
  });

  // 2. Render Queues Table
  const qBody = document.getElementById('table-queues-body');
  qBody.innerHTML = '';
  OBSERVABILITY_DATA.queues.forEach(q => {
    const tr = document.createElement('tr');
    tr.innerHTML = \`
      <td><strong>\${q.name}</strong></td>
      <td>\${q.channel}</td>
      <td>\${q.processed}</td>
      <td>\${q.pending}</td>
      <td><span class="status-badge \${q.status.toLowerCase()}">\${q.status}</span></td>
    \`;
    qBody.appendChild(tr);
  });

  // 3. Render Agents Table
  const aBody = document.getElementById('table-agents-body');
  aBody.innerHTML = '';
  OBSERVABILITY_DATA.agents.forEach(a => {
    const tr = document.createElement('tr');
    tr.innerHTML = \`
      <td><strong>\${a.name}</strong></td>
      <td>\${a.segment}</td>
      <td>\${a.task}</td>
      <td>\${a.uptime}</td>
      <td><span class="status-badge \${a.status.toLowerCase()}">\${a.status}</span></td>
    \`;
    aBody.appendChild(tr);
  });
}

