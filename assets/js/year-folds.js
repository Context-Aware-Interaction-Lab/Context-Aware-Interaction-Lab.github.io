// Year folds on /publications/. Each year is a native <details class="year">; only the newest starts open.
// A link such as /publications/#pub-<id> (from /research/, /join-us/) can point into a closed year, which
// the browser cannot scroll to, so on load and on hashchange this opens the folds around the target and
// scrolls again. It also reveals the Expand all button (hidden in the HTML, so without JavaScript there is
// no dead control; the folds still open by hand). Behaviour is covered by tests/year-folds.test.js.
(() => {
  const folds = Array.from(document.querySelectorAll('details.year'));
  if (!folds.length) return;
  const button = document.querySelector('.year-controls__all');

  const allOpen = () => folds.every(fold => fold.open);
  const syncButton = () => {
    if (button) button.textContent = allOpen() ? 'Collapse all' : 'Expand all';
  };

  const reveal = hash => {
    let id;
    try {
      id = decodeURIComponent(hash.replace(/^#/, ''));
    } catch (error) {
      return;
    }
    const target = id && document.getElementById(id);
    if (!target) return;

    let opened = false;
    const open = fold => {
      if (!fold.open) {
        fold.open = true;
        opened = true;
      }
    };
    for (let node = target; node; node = node.parentElement) {
      if (node.tagName === 'DETAILS') open(node);
    }
    // A year anchor (#2025) names the section, which holds the fold.
    const inner = target.querySelector && target.querySelector('details.year');
    if (inner) open(inner);

    syncButton();
    // Only re-scroll when the layout changed under the browser's own jump to the fragment.
    if (opened) target.scrollIntoView();
  };

  if (button) {
    button.hidden = false;
    button.addEventListener('click', () => {
      const open = !allOpen();
      folds.forEach(fold => { fold.open = open; });
      syncButton();
    });
  }
  folds.forEach(fold => fold.addEventListener('toggle', syncButton));
  window.addEventListener('hashchange', () => reveal(window.location.hash));

  syncButton();
  reveal(window.location.hash);
})();
