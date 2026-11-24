/* Inkrail site — all enhancement code is optional; the static page remains usable without JS. */
(() => {
  'use strict';

  const MEDIA = 'https://raw.githubusercontent.com/Aaryanverma/inkrail/main/screenshots/';
  const images = {
    day: { file: 'inkrail-light-mode.png', alt: 'A welcome note on ivory paper with an embossed IR mark and a walnut typewriter carriage', heroCaption: 'A page that feels like yours.', galleryCaption: 'A welcome note on ivory paper.' },
    night: { file: 'inkrail-night-mode.png', alt: 'Warm light falls across the welcome note and carriage on a dark sheet', heroCaption: 'A gentler way to write after dark.', galleryCaption: 'Warm light follows the writing line.' },
    focus: { file: 'inkrail-focus-mode.png', alt: 'A wide ivory sheet in Focus Mode with a welcome note above the carriage', heroCaption: 'Nothing between you and the words.', galleryCaption: 'More room for the writing line.' },
    embossings: { file: 'inkrail-paper-embossings.png', alt: 'Botanical, Monogram, Sunburst, and Maker’s mark impressions compared on light and dark paper at 45% relief', galleryCaption: 'Four embossings in day and night light.' },
    margins: { file: 'inkrail-paper-margins.png', alt: 'Leafy vines and purple flowers border the sides of a welcome note', galleryCaption: 'A floral border along the margins.' },
    machine: { file: 'inkrail-machine-customizations.png', alt: 'Twelve typewriter carriages in the Machine tab, with Walnut selected', galleryCaption: 'Walnut is one of twelve carriage styles.' },
    desk: { file: 'inkrail-desk-customizations.png', alt: 'The Desk tab previews paired bronze lamps on a walnut desk beside the sheet', galleryCaption: 'A walnut writing desk with paired bronze lamps.' },
    sound: { file: 'inkrail-sound-customizations.png', alt: 'The Sound tab shows six typewriter sound profiles, a volume slider, and a preview button', galleryCaption: 'Choose a typewriter sound and preview its volume.' },
    light: { file: 'inkrail-light-customizations.png', alt: 'The Light tab shows a night writing preview above the lamp intensity and warmth sliders', galleryCaption: 'Adjust the intensity and warmth of the lamp.' },
    storage: { file: 'inkrail-storage-options.png', alt: 'The Storage tab shows the letters folder with Change Location and Show in Finder controls', galleryCaption: 'Choose where the letter library lives.' },
    seal: { file: 'inkrail-seal-options.png', alt: 'The Seal letter dialog previews an AV wax seal alongside inscription, shape, and color controls', galleryCaption: 'Choose the inscription, shape, and wax color.' },
    letter: { file: 'inkrail-letter-with-seal-preview.png', alt: 'A finished letter ends with a red AV wax seal beneath the signature', galleryCaption: 'A wax seal beneath the last line.' }
  };

  const heroImage = document.getElementById('hero-image');
  const heroCaption = document.getElementById('hero-scene-caption');
  const heroCount = document.getElementById('hero-scene-count');
  const heroButtons = [...document.querySelectorAll('[data-hero-scene]')];
  const galleryImage = document.getElementById('gallery-image');
  const galleryCaption = document.getElementById('gallery-caption');
  const galleryCounter = document.getElementById('gallery-counter');
  const galleryButtons = [...document.querySelectorAll('[data-gallery]')];
  let galleryActive = 'day';
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
    const request = ++heroRequest;
    switchImage(heroImage, MEDIA + images[key].file, request, () => heroRequest, () => {
      heroButtons.forEach(b => {
        const active = b === button;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-pressed', String(active));
      });
      heroImage.alt = images[key].alt;
      heroCaption.textContent = images[key].heroCaption;
      heroCount.textContent = heroCounts[key];
    });
  }));

  galleryButtons.forEach((button, index) => {
    button.addEventListener('click', () => {
      const key = button.dataset.gallery;
      if (!images[key]) return;
      const request = ++galleryRequest;
      switchImage(galleryImage, MEDIA + images[key].file, request, () => galleryRequest, () => {
        galleryActive = key;
        galleryButtons.forEach(b => {
          const active = b === button;
          b.classList.toggle('is-active', active);
          b.setAttribute('aria-pressed', String(active));
        });
        galleryImage.alt = images[key].alt;
        galleryCaption.textContent = images[key].galleryCaption;
        galleryCounter.textContent = String(index + 1).padStart(2, '0') + ' — ' + String(galleryButtons.length).padStart(2, '0');
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

  const feedback = document.getElementById('copy-feedback');
  document.querySelectorAll('[data-copy-path]').forEach(button => {
    const code = button.closest('.file-path')?.querySelector('code');
    if (!code) return;
    button.hidden = false;
    button.addEventListener('click', async () => {
      const path = code.textContent;
      let copied = false;
      try { await navigator.clipboard.writeText(path); copied = true; } catch (_) {
        const input = document.createElement('textarea');
        input.value = path;
        input.style.position = 'fixed'; input.style.opacity = '0';
        document.body.appendChild(input); input.select();
        try { copied = document.execCommand('copy'); } catch (_) { /* no clipboard permission */ }
        input.remove();
        button.focus({ preventScroll: true });
      }
      if (feedback) feedback.textContent = copied ? button.dataset.copyPath + ' path copied.' : 'Select the path to copy it.';
    });
  });

  // Keep the releases page as the fallback until this edition's asset exists.
  const version = document.querySelector('[data-release-version]').textContent.trim();
  const repository = 'Aaryanverma/inkrail';
  const controller = new AbortController();
  const fetchTimeout = setTimeout(() => controller.abort(), 6500);
  fetch('https://api.github.com/repos/' + repository + '/releases/tags/' + encodeURIComponent(version), {
    headers: { Accept: 'application/vnd.github+json' }, signal: controller.signal
  })
    .then(response => response.ok ? response.json() : null)
    .then(release => {
      if (!release || release.draft || release.prerelease || release.tag_name !== version) return;
      const uploaded = new Set(release.assets.filter(asset => asset.state === 'uploaded').map(asset => asset.name));
      document.querySelectorAll('[data-asset]').forEach(link => {
        const filename = link.dataset.asset;
        if (uploaded.has(filename)) {
          link.href = 'https://github.com/' + repository + '/releases/download/' +
            encodeURIComponent(version) + '/' + encodeURIComponent(filename);
        }
      });
    })
    .catch(() => { /* Keep the release chooser when GitHub is unavailable. */ })
    .finally(() => clearTimeout(fetchTimeout));
})();
