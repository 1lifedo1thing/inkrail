/* Inkrail site — all enhancement code is optional; the static page remains usable without JS. */
(() => {
  'use strict';

  const MEDIA = 'https://raw.githubusercontent.com/Aaryanverma/inkrail/main/docs/screenshots/';
  const images = {
    day: { file: 'inkrail-light-mode.png', alt: 'Inkrail with light textured paper, a small typewriter carriage, and a botanical desk accent', heroCaption: 'A page that feels like yours.', galleryCaption: 'A fresh page, full of possibility.' },
    night: { file: 'inkrail-night-mode.png', alt: 'Inkrail in night writing mode, with softly illuminated dark paper', heroCaption: 'A gentler way to write after dark.', galleryCaption: 'A gentler way to write after dark.' },
    lamp: { file: 'inkrail-night-lamp.png', alt: 'Inkrail at night, with two bronze desk lamps casting warm light beside the writing page', heroCaption: 'For the ideas that arrive after sunset.', galleryCaption: 'Lamps on. World off.' },
    focus: { file: 'inkrail-focus-mode.png', alt: 'Inkrail Focus Mode, with a wider plain writing page and no desk decorations', heroCaption: 'Nothing between you and the words.', galleryCaption: 'Just a blank page and a thought.' },
    desk: { file: 'inkrail-desk-customization.png', alt: 'Inkrail Make it yours settings, showing desk finishes, paired lamps, and live preview', galleryCaption: 'Your own little corner of the world.' },
    machine: { file: 'inkrail-machine-customization.png', alt: 'Inkrail machine customization settings showing twelve typewriter carriage styles', galleryCaption: 'Twelve small machines, each with its own character.' }
  };

  const heroImage = document.getElementById('hero-image');
  const heroCaption = document.getElementById('hero-scene-caption');
  const heroCount = document.getElementById('hero-scene-count');
  const heroButtons = [...document.querySelectorAll('[data-hero-scene]')];
  const galleryImage = document.getElementById('gallery-image');
  const galleryCaption = document.getElementById('gallery-caption');
  const galleryCounter = document.getElementById('gallery-counter');
  const galleryButtons = [...document.querySelectorAll('[data-gallery]')];
  let galleryActive = 'lamp';
  let heroRequest = 0;
  let galleryRequest = 0;

  function switchImage(img, source, requestId, currentRequest, onReady) {
    if (!img || !source) return;
    img.classList.add('is-changing');
    const preloaded = new Image();
    preloaded.onload = () => {
      if (requestId !== currentRequest()) return;
      img.src = source;
      img.classList.remove('is-changing');
      onReady();
    };
    preloaded.onerror = () => {
      if (requestId !== currentRequest()) return;
      // Keep the previous successful image visible if GitHub's image CDN is unreachable.
      img.classList.remove('is-changing');
    };
    preloaded.src = source;
    if (preloaded.complete && preloaded.naturalWidth > 0) preloaded.onload();
  }

  const heroCounts = { day: '01 / 03', night: '02 / 03', focus: '03 / 03' };
  heroButtons.forEach(button => button.addEventListener('click', () => {
    const key = button.dataset.heroScene;
    if (!(key in heroCounts)) return;
    heroButtons.forEach(b => {
      const active = b === button;
      b.classList.toggle('is-active', active);
      b.setAttribute('aria-pressed', String(active));
    });
    const request = ++heroRequest;
    switchImage(heroImage, MEDIA + images[key].file, request, () => heroRequest, () => {
      heroImage.alt = images[key].alt;
      heroCaption.textContent = images[key].heroCaption;
      heroCount.textContent = heroCounts[key];
    });
  }));

  galleryButtons.forEach((button, index) => {
    button.addEventListener('click', () => {
      const key = button.dataset.gallery;
      if (!images[key]) return;
      galleryActive = key;
      galleryButtons.forEach(b => {
        const active = b === button;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-pressed', String(active));
      });
      const request = ++galleryRequest;
      switchImage(galleryImage, MEDIA + images[key].file, request, () => galleryRequest, () => {
        galleryImage.alt = images[key].alt;
        galleryCaption.textContent = images[key].galleryCaption;
        galleryCounter.textContent = String(index + 1).padStart(2, '0') + ' — 06';
      });
    });
    button.addEventListener('keydown', event => {
      if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp' && event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
      event.preventDefault();
      const next = (index + (event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : -1) + galleryButtons.length) % galleryButtons.length;
      galleryButtons[next].focus();
      galleryButtons[next].click();
    });
  });

  // Load video only when the visitor clicks Play; no third-party iframe on initial page load.
  const videoDialog = document.getElementById('video-dialog');
  const videoContainer = document.getElementById('video-container');
  document.querySelectorAll('[data-open-video]').forEach(button => button.addEventListener('click', () => {
    if (!videoDialog || !videoContainer || typeof videoDialog.showModal !== 'function') {
      window.open('https://youtu.be/oanl6tyIvMo', '_blank', 'noopener,noreferrer');
      return;
    }
    videoContainer.replaceChildren();
    const player = document.createElement('iframe');
    player.src = 'https://www.youtube-nocookie.com/embed/oanl6tyIvMo?autoplay=1&rel=0';
    player.title = 'Inkrail — Video demonstration';
    player.allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share';
    player.referrerPolicy = 'strict-origin-when-cross-origin';
    player.allowFullscreen = true;
    videoContainer.appendChild(player);
    videoDialog.showModal();
  }));
  videoDialog?.addEventListener('close', () => videoContainer.replaceChildren());

  const imageDialog = document.getElementById('image-dialog');
  document.getElementById('gallery-enlarge')?.addEventListener('click', () => {
    const dialogImage = document.getElementById('dialog-image');
    const title = document.getElementById('image-dialog-title');
    if (!dialogImage || !imageDialog || !images[galleryActive]) return;
    dialogImage.src = MEDIA + images[galleryActive].file;
    dialogImage.alt = images[galleryActive].alt;
    title.textContent = 'INKRAIL / ' + (galleryButtons.find(b => b.dataset.gallery === galleryActive)?.querySelector('strong')?.textContent || 'GALLERY').toUpperCase();
    imageDialog.showModal();
  });
  [videoDialog, imageDialog].forEach(dialog => {
    if (!dialog) return;
    dialog.querySelectorAll('[data-close-dialog]').forEach(button => button.addEventListener('click', () => dialog.close()));
    dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  });

  const path = '~/Library/Application Support/Inkrail/';
  const feedback = document.getElementById('copy-feedback');
  document.getElementById('copy-path')?.addEventListener('click', async () => {
    let copied = false;
    try { await navigator.clipboard.writeText(path); copied = true; } catch (_) {
      const input = document.createElement('textarea');
      input.value = path;
      input.style.position = 'fixed'; input.style.opacity = '0';
      document.body.appendChild(input); input.select();
      try { copied = document.execCommand('copy'); } catch (_) { /* no clipboard permission */ }
      input.remove();
    }
    if (feedback) feedback.textContent = copied ? 'Copied to clipboard.' : 'Select the path to copy it.';
  });

  // The static links point to v0.1.1 until GitHub returns the latest release.
  const API = 'https://api.github.com/repos/Aaryanverma/inkrail/releases/latest';
  const downloadLinks = [...document.querySelectorAll('[data-download-link]')];
  const releaseLink = document.querySelector('.closing-github');
  function safeBinaryURL(input) {
    try {
      const u = new URL(input);
      const isGitHub = u.protocol === 'https:' && u.hostname === 'github.com';
      const isRelease = u.pathname.startsWith('/Aaryanverma/inkrail/releases/download/');
      if (isGitHub && isRelease && /\.(zip|dmg)$/i.test(u.pathname)) return u.toString();
    } catch (_) { /* ignore unknown links */ }
    return null;
  }
  function binaryFromRelease(release) {
    const namedAssets = (release.assets || []).filter(a => /(?:^|[^a-z])inkrail(?:[-_. ]|$)/i.test(a.name || '') && /\.(zip|dmg)$/i.test(a.name || ''));
    const asset = namedAssets.find(a => /\.zip$/i.test(a.name)) || namedAssets[0];
    return asset ? safeBinaryURL(asset.browser_download_url) : null;
  }
  const controller = new AbortController();
  const fetchTimeout = setTimeout(() => controller.abort(), 6500);
  fetch(API, { headers: { Accept: 'application/vnd.github+json' }, signal: controller.signal })
    .then(res => { if (!res.ok) throw new Error('GitHub API is unavailable'); return res.json(); })
    .then(release => {
      if (typeof release.tag_name === 'string' && /^v?\d+(\.\d+){1,3}/.test(release.tag_name)) {
        document.querySelectorAll('[data-release-version]').forEach(el => { el.textContent = release.tag_name; });
      }
      const binary = binaryFromRelease(release);
      if (binary) downloadLinks.forEach(link => { link.href = binary; });
      else if (release.html_url?.startsWith('https://github.com/Aaryanverma/inkrail/releases/')) {
        // Never misrepresent a source archive as the application. Use the latest release page instead.
        downloadLinks.forEach(link => {
          link.href = release.html_url;
          link.title = 'Open the latest release to download the macOS application';
        });
      }
      if (releaseLink && release.html_url?.startsWith('https://github.com/Aaryanverma/inkrail/releases/')) releaseLink.href = release.html_url;
    })
    .catch(() => { /* static v0.1.1 download remains available */ })
    .finally(() => clearTimeout(fetchTimeout));
})();
