// crucible-theme.js
// Light / System / Dark switcher.
// Persists in localStorage and applies on every Himem page that loads this script.
// Adds a small unobtrusive floating control in the bottom-right corner.
//
// Other code can call window.setCrucibleTheme('light' | 'system' | 'dark') to
// change mode programmatically (e.g. from a Tweaks panel or a mocked Settings row).

(function () {
  const STORAGE_KEY = 'crucible-theme';
  const MODES = ['light', 'system', 'dark'];

  function readMode() {
    const raw = localStorage.getItem(STORAGE_KEY);
    return MODES.includes(raw) ? raw : 'system';
  }

  function applyMode(mode) {
    const root = document.documentElement;
    if (mode === 'system') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', mode);
  }

  function setTheme(mode) {
    if (!MODES.includes(mode)) mode = 'system';
    localStorage.setItem(STORAGE_KEY, mode);
    applyMode(mode);
    refreshControl();
  }
  window.setCrucibleTheme = setTheme;
  window.getCrucibleTheme = readMode;

  // Apply immediately so we don't flash the wrong scheme.
  applyMode(readMode());

  // Sync across tabs/iframes.
  window.addEventListener('storage', (e) => {
    if (e.key === STORAGE_KEY) {
      applyMode(readMode());
      refreshControl();
    }
  });

  // ──────────────────────────────────────────────────────────
  // Floating control (bottom-right corner).
  // ──────────────────────────────────────────────────────────

  let control;

  const ICONS = {
    light: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="8" cy="8" r="3"/><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3.05 3.05l1.4 1.4M11.55 11.55l1.4 1.4M3.05 12.95l1.4-1.4M11.55 4.45l1.4-1.4"/></svg>',
    system: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M8 2a6 6 0 100 12 6 6 0 000-12z"/><path d="M8 2v12" fill="currentColor" stroke="none"/><path d="M8 2a6 6 0 016 6 6 6 0 01-6 6V2z" fill="currentColor" stroke="none"/></svg>',
    dark:  '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M13.5 9.5A5.5 5.5 0 016.5 2.5 5.5 5.5 0 1013.5 9.5z" fill="currentColor"/></svg>',
  };
  const LABELS = { light: 'Light', system: 'System', dark: 'Dark' };

  function buildControl() {
    if (control) return;
    if (!document.body) {
      document.addEventListener('DOMContentLoaded', buildControl);
      return;
    }
    const host = document.createElement('div');
    host.id = '__crucible-theme-control';
    // Use ! important inline so page CSS can't easily override.
    host.style.cssText = [
      'position:fixed',
      'bottom:14px',
      'right:14px',
      'z-index:2147483646',
      'display:inline-flex',
      'gap:2px',
      'padding:3px',
      'border-radius:999px',
      'background:var(--card, #fffcf6)',
      'border:1px solid var(--hairline, rgba(26,22,18,0.12))',
      'box-shadow:var(--shadow-card, 0 1px 2px rgba(40,25,15,0.06))',
      'font-family:var(--sans, -apple-system, system-ui, sans-serif)',
      'color:var(--ink, #1a1612)',
      'opacity:0.78',
      'transition:opacity 140ms ease',
      'user-select:none',
    ].join(';');
    host.addEventListener('mouseenter', () => host.style.opacity = '1');
    host.addEventListener('mouseleave', () => host.style.opacity = '0.78');

    for (const mode of MODES) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.dataset.mode = mode;
      btn.setAttribute('aria-label', `${LABELS[mode]} theme`);
      btn.title = `${LABELS[mode]} theme`;
      btn.innerHTML = ICONS[mode];
      btn.style.cssText = [
        'width:26px',
        'height:26px',
        'padding:0',
        'border:none',
        'background:transparent',
        'border-radius:999px',
        'display:inline-flex',
        'align-items:center',
        'justify-content:center',
        'cursor:pointer',
        'color:inherit',
        'transition:background 120ms ease, color 120ms ease',
      ].join(';');
      btn.addEventListener('click', () => setTheme(mode));
      host.appendChild(btn);
    }

    document.body.appendChild(host);
    control = host;
    refreshControl();
  }

  function refreshControl() {
    if (!control) return;
    const active = readMode();
    for (const btn of control.querySelectorAll('button')) {
      const isActive = btn.dataset.mode === active;
      btn.style.background = isActive
        ? 'var(--accent-tint, rgba(198,74,28,0.10))'
        : 'transparent';
      btn.style.color = isActive
        ? 'var(--accent, #c64a1c)'
        : 'var(--ink2, rgba(26,22,18,0.66))';
    }
  }

  buildControl();
})();
