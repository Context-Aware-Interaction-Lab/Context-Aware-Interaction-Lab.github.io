// Opens thumbnails and videos on /publications/, and photos on /gallery/, in one native <dialog>.
// Without JS (or without <dialog>) the thumbnail is a plain link to the large image and
// the Video button a plain link to YouTube. No third-party request is made until play is pressed.
//
// Links that share a data-group (the photos of one album) form a set: the dialog then offers Previous and Next
// (buttons, arrow keys, a horizontal swipe), an "n / N" counter, and wraps at either end. A link without a group
// opens alone, as the publication figures do.
(function () {
  var dlg = document.getElementById('figure-dialog');
  if (!dlg || typeof dlg.showModal !== 'function') return;
  var title = dlg.querySelector('.figure-dialog__title');
  var stage = dlg.querySelector('.figure-dialog__stage');
  var caption = dlg.querySelector('.figure-dialog__caption');
  var nav = dlg.querySelector('.figure-dialog__nav');
  var count = dlg.querySelector('.figure-dialog__count');
  var trigger = null;
  var group = [];
  var index = 0;

  function el(tag, cls, attrs) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    for (var k in attrs || {}) n.setAttribute(k, attrs[k]);
    return n;
  }

  function image(a) {
    var img = el('img', 'figure-dialog__img', { src: a.href, alt: a.dataset.alt });
    stage.appendChild(img);
    caption.textContent = a.dataset.caption || a.dataset.alt;
    if (a.dataset.credit) {
      caption.appendChild(el('span', 'figure-dialog__credit')).textContent = ' Photo: ' + a.dataset.credit;
    }
  }

  function video(a) {
    var play = el('button', 'figure-dialog__play', { type: 'button', 'aria-label': 'Play video' });
    play.appendChild(el('img', 'figure-dialog__img', { src: a.dataset.poster, alt: '' }));
    play.appendChild(el('span', 'figure-dialog__triangle', { 'aria-hidden': 'true' }));
    play.addEventListener('click', function () {
      var f = el('iframe', 'figure-dialog__frame', {
        src: 'https://www.youtube-nocookie.com/embed/' + encodeURIComponent(a.dataset.video) + '?autoplay=1',
        title: a.dataset.alt || 'Video',
        allow: 'autoplay; encrypted-media; picture-in-picture',
        allowfullscreen: ''
      });
      stage.textContent = '';
      stage.appendChild(f);
    });
    stage.appendChild(play);
    caption.textContent = a.dataset.alt || '';
  }

  // Fetch the neighbours ahead of the press so stepping does not wait on the network.
  function preload(i) {
    var a = group[(i + group.length) % group.length];
    if (a && a.href) new Image().src = a.href;
  }

  function render(a) {
    trigger = a;
    // A photo in a folded part of the album: open the fold, so closing the dialog can return focus to something visible.
    var fold = a.closest('details');
    if (fold && !fold.open) fold.open = true;
    title.textContent = a.dataset.title;
    stage.textContent = '';
    (a.hasAttribute('data-video') ? video : image)(a);
    if (group.length > 1) {
      count.textContent = (index + 1) + ' / ' + group.length;
      preload(index + 1);
      preload(index - 1);
    }
  }

  function open(a) {
    var g = a.dataset.group;
    group = g ? Array.prototype.slice.call(document.querySelectorAll('a[data-figure][data-group="' + g + '"]')) : [];
    index = Math.max(group.indexOf(a), 0);
    var grouped = group.length > 1;
    nav.hidden = !grouped;
    dlg.classList.toggle('is-grouped', grouped);
    render(a);
    dlg.showModal();
  }

  function step(by) {
    if (group.length < 2) return;
    index = (index + by + group.length) % group.length;
    render(group[index]);
  }

  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-figure], a[data-video]');
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    open(a);
  });

  dlg.querySelector('.figure-dialog__close').addEventListener('click', function () { dlg.close(); });
  dlg.querySelector('.figure-dialog__prev').addEventListener('click', function () { step(-1); });
  dlg.querySelector('.figure-dialog__next').addEventListener('click', function () { step(1); });
  dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  dlg.addEventListener('keydown', function (e) {
    if (group.length < 2 || e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); step(1); }
  });

  // A mostly horizontal drag of more than 50px on the picture steps to the neighbour.
  var touch = null;
  stage.addEventListener('touchstart', function (e) {
    touch = e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null;
  }, { passive: true });
  stage.addEventListener('touchend', function (e) {
    if (!touch || group.length < 2) return;
    var t = e.changedTouches[0];
    var dx = t.clientX - touch.x;
    var dy = t.clientY - touch.y;
    touch = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > 2 * Math.abs(dy)) step(dx < 0 ? 1 : -1);
  }, { passive: true });

  dlg.addEventListener('close', function () {
    stage.textContent = '';   // removes the iframe, which stops playback
    group = [];
    if (trigger) trigger.focus();
  });
})();
