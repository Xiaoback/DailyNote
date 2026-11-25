const demo = document.querySelector('[data-demo]');
const toggle = document.querySelector('[data-motion-toggle]');
if (demo && toggle) {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let playing = !reduced;
  const refresh = () => {
    demo.src = playing ? demo.dataset.animation : demo.dataset.poster;
    toggle.textContent = playing ? toggle.dataset.pause : toggle.dataset.play;
    toggle.setAttribute('aria-pressed', String(playing));
  };
  toggle.hidden = false;
  refresh();
  toggle.addEventListener('click', () => {
    playing = !playing;
    refresh();
  });
}
