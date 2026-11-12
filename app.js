// Perch website: each clip plays only while at least half of it is in view, every clip can be
// paused, nothing starts by itself when the reader prefers reduced motion, and the clone command
// can be copied. No dependencies.
(() => {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const darkScheme = window.matchMedia('(prefers-color-scheme: dark)');
  const clips = [];

  const isDark = () => darkScheme.matches;

  // The poster for the current color scheme. Posters are set only when a clip comes near the
  // viewport, so the page does not download every picture up front.
  function showPoster(clip) {
    const { video } = clip;
    const poster = (isDark() && video.dataset.posterDark) || video.dataset.poster;
    if (poster && video.getAttribute('poster') !== poster) video.setAttribute('poster', poster);
  }

  // A clip with a dark version (the hero) swaps its source when the color scheme changes.
  function applyScheme(clip) {
    const source = clip.video.querySelector('source');
    if (!source || !source.dataset.srcDark) return;
    if (!source.dataset.srcLight) source.dataset.srcLight = source.getAttribute('src');
    const wanted = isDark() ? source.dataset.srcDark : source.dataset.srcLight;
    if (source.getAttribute('src') === wanted) return;
    const wasPlaying = !clip.video.paused;
    source.setAttribute('src', wanted);
    if (clip.near) showPoster(clip);
    clip.video.load();
    if (wasPlaying) play(clip);
  }

  function play(clip) {
    showPoster(clip);
    const started = clip.video.play();
    // A browser may refuse to start a clip. The poster and the play button stay.
    if (started && typeof started.catch === 'function') started.catch(() => render(clip));
  }

  function mayPlay(clip) {
    if (!clip.inView || clip.pausedByReader || document.hidden) return false;
    return !reduceMotion.matches || clip.startedByReader;
  }

  function sync(clip) {
    const allowed = mayPlay(clip);
    if (allowed && clip.video.paused) play(clip);
    else if (!allowed && !clip.video.paused) clip.video.pause();
  }

  function render(clip) {
    const playing = !clip.video.paused;
    clip.toggle.dataset.state = playing ? 'playing' : 'paused';
    clip.toggle.setAttribute('aria-label', `${playing ? 'Pause' : 'Play'} the clip: ${clip.title}`);
  }

  const nearObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const clip = clips.find((c) => c.video === entry.target);
      if (!clip) continue;
      clip.near = true;
      showPoster(clip);
      nearObserver.unobserve(entry.target);
    }
  }, { rootMargin: '25% 0px 25% 0px' });

  const viewObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const clip = clips.find((c) => c.video === entry.target);
      if (!clip) continue;
      clip.inView = entry.isIntersecting && entry.intersectionRatio >= 0.5;
      sync(clip);
    }
  }, { threshold: [0, 0.5] });

  for (const video of document.querySelectorAll('.clip-video')) {
    const figure = video.closest('figure');
    const toggle = figure && figure.querySelector('.clip-toggle');
    if (!toggle) continue;
    video.muted = true;
    const clip = {
      video,
      toggle,
      title: video.dataset.title || 'clip',
      near: video.hasAttribute('data-eager'),
      inView: false,
      pausedByReader: false,
      startedByReader: false,
    };
    clips.push(clip);
    applyScheme(clip);
    if (clip.near) showPoster(clip);
    else nearObserver.observe(video);
    viewObserver.observe(video);

    video.addEventListener('play', () => render(clip));
    video.addEventListener('pause', () => render(clip));
    toggle.addEventListener('click', () => {
      if (clip.video.paused) {
        clip.pausedByReader = false;
        clip.startedByReader = true;
        play(clip);
      } else {
        clip.pausedByReader = true;
        clip.video.pause();
      }
    });
    render(clip);
  }

  const syncAll = () => clips.forEach(sync);
  document.addEventListener('visibilitychange', syncAll);
  reduceMotion.addEventListener('change', syncAll);
  darkScheme.addEventListener('change', () => clips.forEach(applyScheme));

  // Copying the clone command.
  const status = document.getElementById('copy-status');
  for (const button of document.querySelectorAll('[data-copy]')) {
    const target = document.getElementById(button.dataset.copy);
    if (!target) continue;
    let timer = 0;
    const announce = (message) => {
      if (status) status.textContent = message;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        delete button.dataset.state;
        if (status) status.textContent = '';
      }, 2000);
    };
    button.addEventListener('click', async () => {
      const text = target.textContent.trim();
      try {
        await navigator.clipboard.writeText(text);
        button.dataset.state = 'copied';
        announce('Copied the command.');
      } catch {
        // No clipboard access (an old browser, or a page opened from disk): select the text instead.
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        announce('The command is selected, ready to copy.');
      }
    });
  }
})();
