// The Gallery's opening slideshow: one large photo that crossfades to another, drawn at random from every album.
// The pool is read from the photo links already on the page (the closed albums hold one link per photo), so a new
// album joins without any change here. The slideshow ships `hidden`, with a <noscript> still beside it, and is
// revealed here only when there is something to show.
//
// Order: a shuffle without replacement, so every photo shows once before any shows again, and a new round never
// opens on the photo that ended the last. Loading: the large image is fetched and decoded before the fade starts,
// and the next one is fetched while this one shows. Pausing (WCAG 2.2.2): a Pause button, plus automatic holds while
// the pointer is over it (a mouse only; a tap would never leave), while a keyboard user is on Previous, Next or the
// photo, while the tab is hidden, while the lightbox is open and while it is scrolled out of view. A hold or a
// resume restarts the 6 s dwell. With prefers-reduced-motion it starts paused, fades in 0.3 s and does not drift.
// The pure part (order) is exported for tests/gallery-slideshow.test.js.
(function () {
  // A shuffled 0..n-1 (Fisher-Yates). When `avoid` is in the pool it is kept out of the first place.
  function order(n, rand, avoid) {
    var a = [];
    var i;
    for (i = 0; i < n; i++) a.push(i);
    for (i = n - 1; i > 0; i--) {
      var k = Math.floor(rand() * (i + 1));
      var t = a[i]; a[i] = a[k]; a[k] = t;
    }
    if (n > 1 && a[0] === avoid) {
      var s = 1 + Math.floor(rand() * (n - 1));
      var u = a[0]; a[0] = a[s]; a[s] = u;
    }
    return a;
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = { order: order };
  if (typeof document === 'undefined') return;

  var root = document.querySelector('.slideshow');
  if (!root) return;

  var DWELL = 6000;   // ms a photo stays fully shown
  var FADE = 1200;    // ms of the crossfade
  var QUICK = 350;    // ms of the crossfade when a person presses Previous or Next
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

  var pool = Array.prototype.map.call(
    document.querySelectorAll('a[data-figure][data-group^="album-"]'),
    function (a) {
      var album = document.getElementById(a.dataset.group);
      var time = album && album.querySelector('.album__meta time');
      return { href: a.getAttribute('href'), alt: a.dataset.alt, title: a.dataset.title, group: a.dataset.group, when: time ? time.textContent : '' };
    }
  );
  if (!pool.length) return;

  var dlg = document.getElementById('figure-dialog');
  var photoBtn = root.querySelector('.slideshow__photo');
  var layers = Array.prototype.slice.call(root.querySelectorAll('.slideshow__layer'));
  var album = root.querySelector('.slideshow__album');
  var when = root.querySelector('.slideshow__when');
  var toggle = root.querySelector('.slideshow__toggle');
  var prev = root.querySelector('.slideshow__prev');
  var next = root.querySelector('.slideshow__next');
  var live = root.querySelector('.slideshow__announce');

  // The images are made here, not shipped empty: a page without JS never has an <img> without a source.
  layers.forEach(function (layer) {
    var bg = document.createElement('img');
    bg.className = 'slideshow__bg';
    bg.alt = '';
    var fg = document.createElement('img');
    fg.className = 'slideshow__img';
    fg.alt = '';
    layer.appendChild(bg);
    layer.appendChild(fg);
    layer.setAttribute('aria-hidden', 'true');
  });

  var shown = [];         // indexes into pool, in the order they were shown
  var cursor = -1;        // where in `shown` the current photo is (Previous steps back through it)
  var queue = [];         // what is still to come in this round
  var bad = {};           // photos that failed to load
  var current = 1;        // which layer shows the current photo (the first step puts it on layer 0)
  var busy = false;       // loading or fading: manual steps wait
  var timer = null;
  var paused = reduced.matches;
  var hover = false;
  var focus = false;
  var inView = true;
  var preloaded = null;

  function fadeMs(quick) { return reduced.matches ? 300 : quick ? QUICK : FADE; }

  // Which photo a step in this direction lands on, or null.
  function peek(by) {
    if (by < 0) return cursor > 0 ? shown[cursor - 1] : null;
    if (cursor + 1 < shown.length) return shown[cursor + 1];
    if (!queue.length) {
      queue = order(pool.length, Math.random, shown[shown.length - 1]).filter(function (i) { return !bad[i]; });
    }
    return queue.length ? queue[0] : null;
  }

  function commit(by) {
    if (by < 0) { cursor--; return; }
    if (cursor + 1 >= shown.length) shown.push(queue.shift());
    cursor++;
  }

  // Put a photo on a layer and wait until the browser has it decoded, so the fade never starts on a blank frame.
  function ready(layer, photo) {
    var bg = layer.querySelector('.slideshow__bg');
    var fg = layer.querySelector('.slideshow__img');
    bg.src = photo.href;
    fg.alt = photo.alt;
    fg.src = photo.href;
    if (fg.decode) return fg.decode();
    return new Promise(function (resolve, reject) {
      if (fg.complete) return resolve();
      fg.onload = resolve;
      fg.onerror = reject;
    });
  }

  function warm() {
    var i = peek(1);
    if (i == null) return;
    preloaded = new Image();
    preloaded.src = pool[i].href;
  }

  function active() { return !paused && !hover && !focus && !document.hidden && inView && !(dlg && dlg.open); }

  // Re-evaluate every hold: the dwell timer runs only while nothing holds and nothing is loading or fading.
  function sync() {
    var on = active();
    root.classList.toggle('is-held', !on);
    live.setAttribute('aria-live', on ? 'off' : 'polite');
    if (on && !busy && pool.length > 1) {
      if (timer == null) timer = setTimeout(tick, DWELL);
    } else if (timer != null) {
      clearTimeout(timer);
      timer = null;
    }
  }

  function tick() {
    timer = null;
    if (active() && !busy) step(1, false);
  }

  function swap(photo, quick) {
    var incoming = layers[1 - current];
    var outgoing = layers[current];
    root.style.setProperty('--fade', fadeMs(quick) + 'ms');
    incoming.classList.remove('is-active', 'is-leaving');
    void incoming.offsetWidth;   // restart the drift on a layer that has shown a photo before
    incoming.classList.add('is-active');
    incoming.setAttribute('aria-hidden', 'false');
    outgoing.classList.remove('is-active');
    outgoing.classList.add('is-leaving');   // stays opaque beneath until the new photo is fully in: no dip to the backdrop
    outgoing.setAttribute('aria-hidden', 'true');
    current = 1 - current;

    photoBtn.setAttribute('data-opens', photo.href);
    album.textContent = photo.title;
    album.setAttribute('href', '#' + photo.group);
    when.textContent = photo.when;
    prev.setAttribute('aria-disabled', cursor > 0 ? 'false' : 'true');
    if (!active()) live.textContent = photo.alt;   // announced only when a person is driving, never during autoplay

    var finished = false;
    var fallback;
    function done(e) {
      if (finished || (e && (e.target !== incoming || e.propertyName !== 'opacity'))) return;
      finished = true;
      incoming.removeEventListener('transitionend', done);
      clearTimeout(fallback);
      outgoing.classList.remove('is-leaving');
      busy = false;
      warm();
      sync();
    }
    incoming.addEventListener('transitionend', done);
    fallback = setTimeout(done, fadeMs(quick) + 200);   // in case no transition runs (a hidden tab)
  }

  async function step(by, quick) {
    if (busy) return;
    busy = true;
    sync();
    var layer = layers[1 - current];
    for (var tries = 0; tries <= pool.length; tries++) {
      var i = peek(by);
      if (i == null) break;
      try {
        await ready(layer, pool[i]);
      } catch (e) {
        if (by < 0) break;
        bad[i] = true;
        queue.shift();   // skip a photo that will not load
        continue;
      }
      commit(by);
      swap(pool[i], quick);
      return;
    }
    busy = false;
    sync();
  }

  function setToggle() {
    toggle.textContent = paused ? 'Play' : 'Pause';
    toggle.setAttribute('aria-label', paused ? 'Play slideshow' : 'Pause slideshow');
  }

  toggle.addEventListener('click', function () { paused = !paused; setToggle(); sync(); });
  prev.addEventListener('click', function () { step(-1, true); });
  next.addEventListener('click', function () { step(1, true); });

  root.addEventListener('pointerenter', function (e) { if (e.pointerType === 'mouse') { hover = true; sync(); } });
  root.addEventListener('pointerleave', function (e) { if (e.pointerType === 'mouse') { hover = false; sync(); } });
  // A keyboard user on Previous, Next or the photo holds the slideshow; a mouse click that leaves focus there does not.
  // The Pause button never holds, or Play pressed by keyboard would appear to do nothing.
  root.addEventListener('focusin', function (e) {
    if (e.target === toggle) return;
    try { if (!e.target.matches(':focus-visible')) return; } catch (err) { return; }
    focus = true;
    sync();
  });
  root.addEventListener('focusout', function (e) {
    if (e.relatedTarget && root.contains(e.relatedTarget)) return;
    focus = false;
    sync();
  });
  document.addEventListener('visibilitychange', sync);
  if (dlg) dlg.addEventListener('close', sync);
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[entries.length - 1].isIntersecting;
      sync();
    }).observe(root);
  }

  setToggle();
  if (pool.length === 1) root.classList.add('is-single');
  root.hidden = false;
  step(1, true);
})();
