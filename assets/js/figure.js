// Opens thumbnails and videos on /publications/, and albums and photos on /gallery/, in one native <dialog>.
// Without JS (or without <dialog>) a thumbnail is a plain link to the large image, the Video button a plain link to
// YouTube, and an album card is a native <details> that opens in place. No third-party request is made until play
// is pressed.
//
// Links that share a data-group (the photos of one album, group "album-<slug>") form a set. The dialog then has two
// modes. Photo: Previous and Next (buttons, arrow keys, a horizontal swipe), an "n / N" counter, wrapping at either
// end, and an All photos button. Sheet: the album's title, summary and a grid of every photo, opened by pressing
// the album's card; a tile opens that photo. An album of one photo skips the sheet. A link without a group opens
// alone, as the publication figures do. An album's id is its group (details#album-<slug>), and /gallery/#album-<slug>
// opens that album.
(function () {
  var dlg = document.getElementById('figure-dialog');
  if (!dlg || typeof dlg.showModal !== 'function') return;
  var title = dlg.querySelector('.figure-dialog__title');
  var stage = dlg.querySelector('.figure-dialog__stage');
  var caption = dlg.querySelector('.figure-dialog__caption');
  var nav = dlg.querySelector('.figure-dialog__nav');
  var count = dlg.querySelector('.figure-dialog__count');
  var allBtn = dlg.querySelector('.figure-dialog__all');
  var returnTo = null;   // what gets focus when the dialog closes: the card, or the thumbnail last viewed
  var group = [];        // the anchors of the open album
  var index = 0;
  var albumEl = null;    // details.album, when the open photos belong to one
  var viaCard = false;

  function el(tag, cls, attrs) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    for (var k in attrs || {}) n.setAttribute(k, attrs[k]);
    return n;
  }

  function albumOf(id) {
    var e = id ? document.getElementById(id) : null;
    return e && e.classList.contains('album') ? e : null;
  }

  function groupOf(id) {
    return id ? Array.prototype.slice.call(document.querySelectorAll('a[data-figure][data-group="' + id + '"]')) : [];
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

  function showPhoto(a) {
    var many = group.length > 1;
    dlg.classList.remove('is-sheet');
    dlg.classList.toggle('is-grouped', many);
    nav.hidden = !many;
    allBtn.hidden = !(many && albumEl);
    if (!viaCard) returnTo = a;   // opened from a tile: focus goes back to the tile last viewed
    title.textContent = a.dataset.title;
    stage.textContent = '';
    (a.hasAttribute('data-video') ? video : image)(a);
    if (many) {
      count.textContent = (index + 1) + ' / ' + group.length;
      preload(index + 1);
      preload(index - 1);
    }
  }

  // The album's contact sheet: its title, a line of facts, the summary and link written in the card's body, then a
  // grid of every photo built from the same links (the thumbnails are the ones the links already carry).
  function showSheet() {
    dlg.classList.remove('is-grouped');
    dlg.classList.add('is-sheet');
    nav.hidden = true;
    title.textContent = albumEl.querySelector('.album__title').textContent;
    caption.textContent = '';
    stage.textContent = '';
    var intro = el('div', 'album__intro');
    var meta = albumEl.querySelector('.album__meta');
    if (meta) intro.appendChild(el('p', 'album__meta')).textContent = meta.textContent;
    var summary = albumEl.querySelector('.album__summary');
    if (summary) intro.appendChild(summary.cloneNode(true));
    var link = albumEl.querySelector('.album__link');
    if (link) intro.appendChild(link.cloneNode(true));
    stage.appendChild(intro);
    var grid = el('ul', 'album__grid album__sheet');
    group.forEach(function (a, i) {
      var thumb = a.querySelector('img');
      var li = el('li', 'album__photo');
      li.style.setProperty('--ar', a.parentNode.style.getPropertyValue('--ar'));
      var b = el('button', null, { type: 'button', 'aria-label': a.dataset.alt });
      b.appendChild(el('img', null, { src: thumb.getAttribute('src'), alt: '', loading: 'lazy' }));
      b.addEventListener('click', function () {
        index = i;
        showPhoto(group[i]);
        allBtn.focus();   // the tile just left the page; keep focus inside the dialog
      });
      li.appendChild(b);
      grid.appendChild(li);
    });
    stage.appendChild(grid);
  }

  function backToSheet() {
    showSheet();
    var tile = stage.querySelectorAll('.album__sheet button')[index];
    if (tile) {
      tile.focus();
      tile.scrollIntoView({ block: 'nearest' });
    }
  }

  function setHash(id) {
    try { history.replaceState(null, '', location.pathname + location.search + (id ? '#' + id : '')); } catch (e) { /* file:// */ }
  }

  // A card was pressed: open that album, on its contact sheet (or straight on the photo if there is only one).
  function openAlbum(details) {
    var photos = groupOf(details.id);
    if (!photos.length) return;
    viaCard = true;
    albumEl = details;
    group = photos;
    index = 0;
    returnTo = details.querySelector('summary');
    if (group.length > 1) showSheet(); else showPhoto(group[0]);
    dlg.showModal();
    setHash(details.id);
  }

  // A thumbnail or video link, or a photo link, was pressed.
  function open(a) {
    viaCard = false;
    albumEl = albumOf(a.dataset.group);
    group = groupOf(a.dataset.group);
    index = Math.max(group.indexOf(a), 0);
    showPhoto(a);
    dlg.showModal();
  }

  function step(by) {
    if (group.length < 2 || dlg.classList.contains('is-sheet')) return;
    index = (index + by + group.length) % group.length;
    showPhoto(group[index]);
  }

  function openFromHash() {
    if (dlg.open) return;
    var album = albumOf(decodeURIComponent(location.hash.slice(1)));
    if (album && !album.closest('[hidden]')) openAlbum(album);
  }

  document.addEventListener('click', function (e) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || !e.target.closest) return;
    var card = e.target.closest('details.album > summary');
    if (card) {
      e.preventDefault();   // the card does not open in place; it opens the lightbox
      openAlbum(card.parentNode);
      return;
    }
    var a = e.target.closest('a[data-figure], a[data-video]');
    if (!a) return;
    e.preventDefault();
    open(a);
  });

  dlg.querySelector('.figure-dialog__close').addEventListener('click', function () { dlg.close(); });
  dlg.querySelector('.figure-dialog__prev').addEventListener('click', function () { step(-1); });
  dlg.querySelector('.figure-dialog__next').addEventListener('click', function () { step(1); });
  allBtn.addEventListener('click', backToSheet);
  dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  dlg.addEventListener('keydown', function (e) {
    if (e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); step(1); }
  });

  // A mostly horizontal drag of more than 50px on the picture steps to the neighbour.
  var touch = null;
  stage.addEventListener('touchstart', function (e) {
    touch = e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null;
  }, { passive: true });
  stage.addEventListener('touchend', function (e) {
    if (!touch) return;
    var t = e.changedTouches[0];
    var dx = t.clientX - touch.x;
    var dy = t.clientY - touch.y;
    touch = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > 2 * Math.abs(dy)) step(dx < 0 ? 1 : -1);
  }, { passive: true });

  dlg.addEventListener('close', function () {
    stage.textContent = '';   // removes the iframe, which stops playback
    if (viaCard && albumEl && location.hash === '#' + albumEl.id) setHash('');
    group = [];
    albumEl = null;
    if (returnTo) returnTo.focus();
  });

  window.addEventListener('hashchange', openFromHash);
  openFromHash();
})();
