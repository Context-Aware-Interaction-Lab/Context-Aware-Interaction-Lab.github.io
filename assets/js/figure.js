// Opens thumbnails and videos on /publications/ in one native <dialog>.
// Without JS (or without <dialog>) the thumbnail is a plain link to the large image and
// the Video button a plain link to YouTube. No third-party request is made until play is pressed.
(function () {
  var dlg = document.getElementById('figure-dialog');
  if (!dlg || typeof dlg.showModal !== 'function') return;
  var title = dlg.querySelector('.figure-dialog__title');
  var stage = dlg.querySelector('.figure-dialog__stage');
  var caption = dlg.querySelector('.figure-dialog__caption');
  var trigger = null;

  function el(tag, cls, attrs) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    for (var k in attrs || {}) n.setAttribute(k, attrs[k]);
    return n;
  }

  function show(a, build) {
    trigger = a;
    title.textContent = a.dataset.title;
    stage.textContent = '';
    build();
    dlg.showModal();
  }

  function image(a) {
    var img = el('img', 'figure-dialog__img', { src: a.href, alt: a.dataset.alt });
    stage.appendChild(img);
    caption.textContent = a.dataset.alt;
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

  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-figure], a[data-video]');
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    show(a, function () { (a.hasAttribute('data-video') ? video : image)(a); });
  });

  dlg.querySelector('.figure-dialog__close').addEventListener('click', function () { dlg.close(); });
  dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  dlg.addEventListener('close', function () {
    stage.textContent = '';   // removes the iframe, which stops playback
    if (trigger) trigger.focus();
  });
})();
