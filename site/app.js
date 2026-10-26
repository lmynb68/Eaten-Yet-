const menuToggle = document.querySelector('[data-menu-toggle]');
const nav = document.querySelector('[data-nav]');

if (menuToggle && nav) {
  const closeMenu = () => {
    menuToggle.setAttribute('aria-expanded', 'false');
    nav.classList.remove('is-open');
  };

  menuToggle.addEventListener('click', () => {
    const open = menuToggle.getAttribute('aria-expanded') !== 'true';
    menuToggle.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('is-open', open);
  });
  nav.querySelectorAll('a').forEach((link) => link.addEventListener('click', closeMenu));
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeMenu();
  });
}

const header = document.querySelector('[data-header]');
if (header) {
  const updateHeader = () => header.classList.toggle('is-scrolled', window.scrollY > 8);
  updateHeader();
  window.addEventListener('scroll', updateHeader, { passive: true });
}

const gallery = document.querySelector('[data-gallery]');
if (gallery) {
  const image = gallery.querySelector('[data-gallery-image]');
  const title = gallery.querySelector('[data-gallery-title]');
  const caption = gallery.querySelector('[data-gallery-caption]');
  const counter = gallery.querySelector('.gallery-note span');
  const tabs = [...gallery.querySelectorAll('[role="tab"]')];

  const selectTab = (tab) => {
    tabs.forEach((item) => {
      const selected = item === tab;
      item.classList.toggle('is-active', selected);
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
    });
    image.src = tab.dataset.src;
    image.alt = tab.dataset.alt;
    title.textContent = tab.dataset.title;
    caption.textContent = tab.dataset.caption;
    counter.textContent = `${String(tabs.indexOf(tab) + 1).padStart(2, '0')} / ${String(tabs.length).padStart(2, '0')}`;
  };

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      let nextIndex = index;
      if (event.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') nextIndex = 0;
      if (event.key === 'End') nextIndex = tabs.length - 1;
      tabs[nextIndex].focus();
      selectTab(tabs[nextIndex]);
    });
  });
}

const formatMegabytes = (bytes) => `${(bytes / 1024 / 1024).toFixed(1)} MiB`;

fetch('release.json')
  .then((response) => {
    if (!response.ok) throw new Error('release.json unavailable');
    return response.json();
  })
  .then((release) => {
    const arm64 = release.assets.find((asset) => asset.abi === 'arm64-v8a');
    const universal = release.assets.find((asset) => asset.abi.includes(','));
    if (!arm64 || !universal) throw new Error('release assets incomplete');

    document.querySelectorAll('[data-primary-download], [data-arm64-download]').forEach((link) => { link.href = arm64.url; });
    document.querySelector('[data-arm64-size]').textContent = formatMegabytes(arm64.bytes);
    document.querySelector('[data-arm64-sha]').textContent = arm64.sha256;
    document.querySelector('[data-universal-download]').href = universal.url;
    document.querySelector('[data-universal-size]').textContent = formatMegabytes(universal.bytes);
    document.querySelector('[data-universal-sha]').textContent = universal.sha256;
    document.querySelector('[data-release-status]').dataset.releaseStatus = 'ready';
  })
  .catch(() => {
    const options = document.querySelector('[data-release-status]');
    if (options) options.dataset.releaseStatus = 'fallback';
  });

const copyButton = document.querySelector('[data-copy-release]');
const releaseLink = document.querySelector('[data-release-link]');
const copyStatus = document.querySelector('[data-copy-status]');

if (copyButton && releaseLink && copyStatus) {
  copyButton.addEventListener('click', async () => {
    const url = releaseLink.href;
    try {
      await navigator.clipboard.writeText(url);
      copyStatus.textContent = '发布页链接已复制。';
      copyButton.textContent = '已复制';
    } catch {
      copyStatus.textContent = '浏览器未允许复制，请选择上方明文链接后手动复制。';
      releaseLink.focus();
    }
  });
}
