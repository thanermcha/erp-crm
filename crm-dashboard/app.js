/* ── GrowERP CRM Dashboard — App Logic ── */

document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  renderOverview();
  renderPersonas();
  renderLandingPages();
  renderCampaigns();
  renderMessages();
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
