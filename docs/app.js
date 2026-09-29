const FAMILY_LABELS = {
  cyberdyne: 'CYBERDYNE',
  cyberpunk: 'CYBERPUNK',
  default: 'CLASSICS / CURATED',
  dystopian: 'DYSTOPIAN',
  neosynth: 'NEOSYNTH',
  synthwave: 'SYNTHWAVE'
};
const $ = (selector) => document.querySelector(selector);
const menu = $('#themeMenu');
const trigger = $('#themeTrigger');
const options = $('#themeOptions');
let registry;
let selected = 'cyberpunk-neon';

function label(slug) {
  return slug.replaceAll('-', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function palette(theme) {
  return {
    '--bg': `#${theme.bg}`,
    '--panel': `#${theme.panel}`,
    '--line': `#${theme.line}`,
    '--white': `#${theme.white}`,
    '--muted': `#${theme.muted}`,
    '--cyan': `#${theme.cyan}`,
    '--acid': `#${theme.acid_green}`,
    '--pink': `#${theme.hot_pink}`,
    '--purple': `#${theme.purple}`,
    '--orange': `#${theme.orange}`,
    '--red': `#${theme.red}`
  };
}

function applyTheme(name, persist = true) {
  const theme = registry.themes[name];
  if (!theme) return;
  selected = name;
  Object.entries(palette(theme)).forEach(([property, value]) => document.documentElement.style.setProperty(property, value));
  document.documentElement.dataset.theme = name;
  $('#themeCurrent').textContent = label(name).toUpperCase();
  $('#themeOptions').querySelectorAll('[data-theme]').forEach((button) => {
    const active = button.dataset.theme === name;
    button.setAttribute('aria-pressed', String(active));
    button.querySelector('.theme-check').textContent = active ? '✓' : '';
  });
  if (persist) {
    try { localStorage.setItem('cyberwin-theme', name); } catch { /* Private browsing can disable storage. */ }
  }
}

function makeOption(name) {
  const colors = ['bg', 'cyan', 'acid_green', 'hot_pink', 'purple'].map((role) => registry.themes[name][role]);
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'theme-option';
  button.dataset.theme = name;
  button.setAttribute('aria-pressed', 'false');
  button.innerHTML = `<span class="theme-swatches" aria-hidden="true">${colors.map((color) => `<i style="background:#${color}"></i>`).join('')}</span><span class="theme-name">${label(name)}</span><span class="theme-check" aria-hidden="true"></span>`;
  button.addEventListener('click', () => {
    applyTheme(name);
    closeMenu();
    trigger.focus();
  });
  return button;
}

function renderOptions(query = '') {
  const needle = query.trim().toLowerCase().replaceAll(' ', '-');
  options.replaceChildren();
  let matchCount = 0;
  Object.entries(registry.families).forEach(([family, names]) => {
    const matches = names.filter((name) => !needle || name.includes(needle) || family.includes(needle));
    if (!matches.length) return;
    const group = document.createElement('section');
    group.className = 'theme-group';
    const heading = document.createElement('h3');
    heading.className = 'theme-group-title';
    heading.textContent = `${FAMILY_LABELS[family] || family.toUpperCase()}  /  ${matches.length}`;
    group.append(heading, ...matches.map(makeOption));
    options.append(group);
    matchCount += matches.length;
  });
  if (!matchCount) {
    const empty = document.createElement('p');
    empty.className = 'theme-empty';
    empty.textContent = 'No matching palette. Try another name.';
    options.append(empty);
  }
  applyTheme(selected, false);
}

function openMenu() {
  menu.hidden = false;
  trigger.setAttribute('aria-expanded', 'true');
  $('#themeSearch').focus();
}

function closeMenu() {
  menu.hidden = true;
  trigger.setAttribute('aria-expanded', 'false');
}

trigger.addEventListener('click', () => menu.hidden ? openMenu() : closeMenu());
menu.addEventListener('click', (event) => event.stopPropagation());
document.addEventListener('click', (event) => {
  if (!menu.hidden && !menu.contains(event.target) && !trigger.contains(event.target)) closeMenu();
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !menu.hidden) {
    closeMenu();
    trigger.focus();
  }
  if (event.key === '/' && !event.ctrlKey && !event.metaKey && !['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) {
    event.preventDefault();
    if (menu.hidden) openMenu();
    $('#themeSearch').focus();
  }
});
$('#themeSearch').addEventListener('input', (event) => renderOptions(event.target.value));

const navToggle = $('#navToggle');
navToggle.addEventListener('click', () => {
  const expanded = navToggle.getAttribute('aria-expanded') === 'true';
  navToggle.setAttribute('aria-expanded', String(!expanded));
  navToggle.setAttribute('aria-label', expanded ? 'Open navigation' : 'Close navigation');
  $('.main-nav').classList.toggle('open', !expanded);
});
$('.main-nav').addEventListener('click', (event) => {
  if (event.target.closest('a')) {
    $('.main-nav').classList.remove('open');
    navToggle.setAttribute('aria-expanded', 'false');
    navToggle.setAttribute('aria-label', 'Open navigation');
  }
});

$('#copyInstall').addEventListener('click', async () => {
  const command = $('#installCommand');
  try {
    await navigator.clipboard.writeText(command.textContent.trim());
    $('#copyStatus').textContent = 'COMMAND COPIED';
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(command);
    selection.removeAllRanges();
    selection.addRange(range);
    $('#copyStatus').textContent = 'SELECTED — PRESS CTRL/CMD+C';
  }
});

fetch(new URL('data/themes.json', document.currentScript.src))
  .then((response) => {
    if (!response.ok) throw new Error(`Theme registry unavailable (${response.status})`);
    return response.json();
  })
  .then((data) => {
    registry = data;
    const count = Object.values(registry.families).reduce((total, family) => total + family.length, 0);
    if (count !== 72) throw new Error(`Expected 72 Cybercore themes, found ${count}`);
    try {
      const saved = localStorage.getItem('cyberwin-theme');
      if (saved && registry.themes[saved]) selected = saved;
    } catch { /* Fall back to the default theme. */ }
    renderOptions();
    applyTheme(selected, false);
  })
  .catch((error) => {
    console.error(error);
    $('#themeCurrent').textContent = 'THEME REGISTRY OFFLINE';
    options.innerHTML = '<p class="theme-empty">The palette registry could not be loaded. Reload the page to try again.</p>';
  });
