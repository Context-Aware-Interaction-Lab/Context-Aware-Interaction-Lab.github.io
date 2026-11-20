// The album strips on /gallery/ (and the specimen on /design-language/): each year's album cards sit on one horizontal
// scroll-snap strip. Without this script the strip is still a row you can scroll and swipe; with it, a strip that
// overflows becomes a coverflow:
//   - The active card sits in the middle, much bigger, and its neighbours shrink and fade (CSS reads the --m variable
//     this script sets on each card: 1 at the strip's centre, easing to 0 a card's pitch away). The card under the mouse,
//     or with keyboard focus, is magnified by CSS alone (--h), whether or not a strip overflows.
//   - Kept smooth on purpose (see the .album rules in site.css): the lens is applied frame by frame with no transition, the
//     shadow is a fading pseudo-element, positions are all read before any is written, a drag is written once per frame,
//     and snapping stays off after a drag until the strip has arrived. Tracing showed the first version spent ~890ms
//     rasterising over seven interactions, mostly repainting an animated box-shadow; this one spends ~360ms.
//   - A mouse can drag the strip. It follows the pointer, and on release glides on at the pointer's own speed (a critically
//     damped spring: the browser's smooth scroll would start from a standstill, so the strip would stop dead and re-accelerate)
//     and settles with a card centred. Hover is off while it drags and glides, so only the lens makes a card big. A drag never
//     opens a card. Touch and trackpad already scroll natively, one card per swipe.
//   - Left and right arrows (shown only while the strip overflows, dimmed at either end) step one card; quick presses add
//     up. Left and right arrow keys move focus card to card, and a card focused by keyboard is brought to the middle.
// Whether a strip overflows is decided from the cards' own width, never from scrollWidth: an overflowing strip gets
// centring padding, which would make every strip look as if it overflowed. It is recomputed on scroll, on resize and when
// a filter chip hides or shows albums (that changes the contents but not the strip's box, so ResizeObserver alone would
// miss it). The pure parts (magnification, step, edges, overflows, snapTarget) are exported for tests/gallery-carousel.test.js.
(function () {
  // How magnified a card is, 0..1, by how far its centre is from the strip's centre: 1 at the centre, easing to 0 at
  // `span` pixels away and beyond. A cosine ease, so the lens has no visible corner at either end.
  function magnification(offset, span) {
    if (!(span > 0)) return 0;
    var r = Math.abs(offset) / span;
    if (r >= 1) return 0;
    return 0.5 * (1 + Math.cos(Math.PI * r));
  }

  // Pixels one arrow press scrolls: a card and the gap after it, forward (1) or back (-1).
  function step(card, gap, dir) {
    return dir * (card + gap);
  }

  // Where a strip is: does it overflow, is it at the start, is it at the end. One pixel of slack, because scroll
  // positions and widths round differently.
  function edges(scrollLeft, clientWidth, scrollWidth) {
    return {
      overflows: scrollWidth - clientWidth > 1,
      atStart: scrollLeft <= 1,
      atEnd: scrollLeft + clientWidth >= scrollWidth - 1
    };
  }

  // Do `count` cards of width `card`, `gap` apart, fit in `width`? Counted from the cards, not measured from the strip.
  function overflows(count, card, gap, width) {
    if (!(count > 1)) return false;
    return count * card + (count - 1) * gap > width + 1;
  }

  // Where a strip settles after a drag: the scroll position that centres the card nearest to where the throw would carry
  // it. `centres` are the cards' centres in the strip's scrolled coordinates, `scrollVelocity` is px per ms (positive =
  // scrolling forward), `projectMs` how far ahead to project, and `limit` how far from the current centre a throw may reach,
  // so one hard flick cannot fling past many cards. Never negative; the browser clamps the far end.
  function snapTarget(scrollLeft, clientWidth, centres, scrollVelocity, projectMs, limit) {
    if (!centres.length) return scrollLeft;
    var here = scrollLeft + clientWidth / 2;
    var projected = here + scrollVelocity * projectMs;
    projected = Math.max(here - limit, Math.min(here + limit, projected));
    var best = centres[0];
    for (var i = 1; i < centres.length; i++) {
      if (Math.abs(centres[i] - projected) < Math.abs(best - projected)) best = centres[i];
    }
    return Math.max(0, best - clientWidth / 2);
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { magnification: magnification, step: step, edges: edges, overflows: overflows, snapTarget: snapTarget };
  }
  if (typeof document === 'undefined') return;

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

  function init(box) {
    var strip = box.querySelector('.album-cards');
    var prev = box.querySelector('.album-carousel__prev');
    var next = box.querySelector('.album-carousel__next');
    if (!strip || !prev || !next) return;
    var queued = false;

    function shown() {
      return Array.prototype.slice.call(strip.querySelectorAll('.album:not([hidden])'));
    }

    function gap() {
      return parseFloat(window.getComputedStyle(strip).columnGap) || 0;
    }

    function pitch() {
      var albums = shown();
      return albums.length ? albums[0].offsetWidth + gap() : 0;
    }

    // Card centres in the strip's scrolled coordinates, so they compare with scrollLeft + clientWidth / 2.
    function centres() {
      var left = strip.getBoundingClientRect().left - strip.scrollLeft;
      return shown().map(function (a) {
        var r = a.getBoundingClientRect();
        return r.left - left + r.width / 2;
      });
    }

    function measure() {
      queued = false;
      var albums = shown();
      var over = overflows(albums.length, albums.length ? albums[0].offsetWidth : 0, gap(), box.clientWidth);
      box.classList.toggle('is-overflowing', over);
      var e = edges(strip.scrollLeft, strip.clientWidth, strip.scrollWidth);
      prev.hidden = next.hidden = !over;
      prev.setAttribute('aria-disabled', e.atStart ? 'true' : 'false');
      next.setAttribute('aria-disabled', e.atEnd ? 'true' : 'false');
      // The lens: one pitch either side of the strip's centre, so at rest exactly one card is fully magnified.
      // Read every position first and write afterwards: a write between two reads would force a layout for each card.
      var p = pitch();
      var rect = strip.getBoundingClientRect();
      var centre = rect.left + rect.width / 2;
      var all = Array.prototype.slice.call(strip.querySelectorAll('.album'));
      var lens = all.map(function (a) {
        if (!over || a.hidden) return 0;
        var r = a.getBoundingClientRect();
        return magnification(r.left + r.width / 2 - centre, p);
      });
      all.forEach(function (a, i) { a.style.setProperty('--m', lens[i].toFixed(3)); });
    }

    // While a strip moves its cards get their own compositor layers (CSS: .is-moving), so scaling and fading them costs no
    // repainting; a moment after it stops they are released, so they are drawn crisp at their resting size.
    var rest = null;
    function moving() {
      box.classList.add('is-moving');
      window.clearTimeout(rest);
      rest = window.setTimeout(function () { box.classList.remove('is-moving'); }, 180);
    }

    function schedule() {
      if (queued) return;
      queued = true;
      window.requestAnimationFrame(measure);
    }

    function onScroll() {
      moving();
      schedule();
    }

    // ---- arrows. Where an arrow-started scroll is heading, while it is in flight: a press made mid-animation adds to
    // this target instead of to wherever the smooth scroll has got to, so quick presses add up and none is lost.
    var target = null;
    var settle = null;

    function go(dir) {
      var first = shown()[0];
      if (!first) return;
      cancelGlide();
      var max = strip.scrollWidth - strip.clientWidth;
      var from = target == null ? strip.scrollLeft : target;
      target = Math.max(0, Math.min(max, from + step(first.offsetWidth, gap(), dir)));
      strip.scrollTo({ left: target, behavior: reduced.matches ? 'auto' : 'smooth' });
      // scrollend is not everywhere yet, so also let go of the target a moment after the last press.
      window.clearTimeout(settle);
      settle = window.setTimeout(function () { target = null; }, 700);
    }

    prev.addEventListener('click', function () { go(-1); });
    next.addEventListener('click', function () { go(1); });
    strip.addEventListener('scrollend', function () { target = null; });
    strip.addEventListener('wheel', function () { cancelGlide(); }, { passive: true });
    strip.addEventListener('touchstart', function () { cancelGlide(); }, { passive: true });

    // ---- mouse drag. Touch and pens scroll natively, so only a mouse is handled here. A press is not a drag until it
    // has moved a few pixels, so a plain click still reaches the card; once it is one, snapping is switched off so the
    // strip can follow the pointer. On release the strip does not hand over to the browser's smooth scroll (which always
    // starts from a standstill, so the strip would stop dead and re-accelerate): it glides on under its own critically
    // damped spring that starts at the pointer's speed, so the motion is continuous through the release.
    var drag = null;
    var swallow = false;
    var arrival = 0;      // identifies the latest glide, so a new press cancels the previous one
    var gliding = false;
    var written = false;  // a frame is already queued to write the drag position

    // Hover is switched off while a strip is dragged or gliding (CSS, .is-dragging), or the card under the pointer would stay
    // big while the lens makes another one big; it comes back when the mouse next moves (.after-drag).
    var still = null;     // where the pointer was when the glide ended
    function finish() {
      gliding = false;
      strip.classList.remove('is-dragging');
      strip.classList.add('after-drag');
      schedule();
    }

    strip.addEventListener('pointermove', function (e) {
      if (!still || e.pointerType !== 'mouse') return;
      if (Math.abs(e.clientX - still.x) + Math.abs(e.clientY - still.y) > 3) {
        strip.classList.remove('after-drag');
        still = null;
      }
    });

    // Anything else that moves the strip (an arrow, the wheel, a touch, a focused card) takes over from a glide in progress
    // instead of being overwritten by it on the next frame; snapping comes back and settles the strip where it is.
    function cancelGlide() {
      if (!gliding) return;
      arrival++;
      gliding = false;
      strip.classList.remove('is-dragging');
    }

    // Glide from `from` to `to` starting at velocity `v0` (px per ms), critically damped so that it never overshoots: the
    // starting speed is capped at what would just reach the target.
    function glide(from, to, v0) {
      var mine = ++arrival;
      gliding = true;
      if (reduced.matches) { strip.scrollLeft = to; measure(); finish(); return; }
      var w = 0.012; // 1/ms: settles in about 400ms
      var a = from - to;
      var v = v0;
      if (a !== 0 && v * -a > 0) v = Math.sign(v) * Math.min(Math.abs(v), w * Math.abs(a)); // toward the target: no overshoot
      var b = v + w * a;
      var t0 = window.performance.now();
      (function frame() {
        if (mine !== arrival) return; // a press has taken the strip back
        var t = window.performance.now() - t0;
        var e = Math.exp(-w * t);
        var x = to + (a + b * t) * e;
        var speed = (b - w * (a + b * t)) * e;
        var done = (Math.abs(x - to) < 0.5 && Math.abs(speed) < 0.02) || t > 1500;
        strip.scrollLeft = done ? to : x;
        measure(); // the lens in the same frame as the position it is for
        if (done) finish(); else window.requestAnimationFrame(frame);
      })();
    }

    function endDrag(e) {
      if (!drag) return;
      var d = drag;
      drag = null;
      if (!d.active) {
        // A press that grabbed a moving strip and did not drag it: let it carry on to the nearest card.
        if (d.interrupted) glide(strip.scrollLeft, snapTarget(strip.scrollLeft, strip.clientWidth, centres(), 0, 220, 0), 0);
        return;
      }
      if (d.want != null) strip.scrollLeft = d.want; // the last position may still be waiting for its frame
      try { strip.releasePointerCapture(d.id); } catch (err) { /* already released */ }
      swallow = true;
      window.setTimeout(function () { swallow = false; }, 0);
      still = { x: d.lastX, y: d.lastY };
      var sinceMove = (e && e.timeStamp ? e.timeStamp : 0) - d.t;
      // Pointer velocity over the last moments of the drag (px per ms); a pause before letting go means no throw.
      var scrollVelocity = sinceMove > 80 ? 0 : -d.v;
      var from = strip.scrollLeft;
      var to = snapTarget(from, strip.clientWidth, centres(), scrollVelocity, 220, pitch() * 0.9);
      glide(from, to, scrollVelocity);
    }

    strip.addEventListener('pointerdown', function (e) {
      if (e.pointerType !== 'mouse' || e.button !== 0 || !box.classList.contains('is-overflowing')) return;
      var grabbed = gliding;
      arrival++; // cancels a glide that is still running: the strip is taken back
      gliding = false;
      strip.classList.remove('after-drag');
      still = null;
      drag = { id: e.pointerId, x: e.clientX, left: strip.scrollLeft, active: false, v: 0, t: e.timeStamp, lastX: e.clientX, lastY: e.clientY, interrupted: grabbed };
    });

    strip.addEventListener('pointermove', function (e) {
      if (!drag || e.pointerId !== drag.id) return;
      var dx = e.clientX - drag.x;
      if (!drag.active) {
        if (Math.abs(dx) < 6) return;
        drag.active = true;
        strip.classList.add('is-dragging');
        try { strip.setPointerCapture(drag.id); } catch (err) { /* the pointer is gone */ }
        // The first few pixels were a dead zone, not a drag: start from here, so the strip does not jump by them.
        drag.x = e.clientX;
        drag.left = strip.scrollLeft;
        dx = 0;
      }
      drag.want = drag.left - dx; // the position to show; written once per frame, however many pointer events arrive
      if (!written) {
        written = true;
        window.requestAnimationFrame(function () {
          written = false;
          if (drag && drag.active) {
            strip.scrollLeft = drag.want;
            measure(); // the lens in the same frame as the position it is for
          }
        });
      }
      moving();
      var dt = e.timeStamp - drag.t;
      if (dt > 0) drag.v = 0.8 * drag.v + 0.2 * ((e.clientX - drag.lastX) / dt); // smoothed, so one jittery sample does not throw it
      drag.lastX = e.clientX;
      drag.lastY = e.clientY;
      drag.t = e.timeStamp;
    });

    strip.addEventListener('pointerup', endDrag);
    strip.addEventListener('pointercancel', endDrag);
    strip.addEventListener('lostpointercapture', endDrag);
    // A drag that ends over a card could click it; swallow that one click. Defensive and NOT exercised by the tests: in
    // Chromium the pointer capture already sends the click to the strip, where nothing opens, so removing this changes
    // nothing there. It is for any browser that clicks the card the drag ends over.
    strip.addEventListener('click', function (e) {
      if (!swallow) return;
      e.preventDefault();
      e.stopPropagation();
    }, true);
    // The browser's own image drag would take the pointer away from the strip.
    strip.addEventListener('dragstart', function (e) { e.preventDefault(); });

    // ---- keyboard. Left and right arrow keys move focus from card to card, and a card focused by keyboard (a tab, or an
    // arrow key) is brought to the middle. A card focused by a mouse click is left where it is.
    strip.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      var current = e.target.closest ? e.target.closest('.album') : null;
      var albums = shown();
      var at = albums.indexOf(current);
      if (at < 0) return;
      var to = albums[at + (e.key === 'ArrowRight' ? 1 : -1)];
      if (!to) return;
      e.preventDefault();
      to.querySelector('summary').focus();
    });
    strip.addEventListener('focusin', function (e) {
      var a = e.target.closest ? e.target.closest('.album') : null;
      if (!a || !box.classList.contains('is-overflowing')) return;
      try { if (!e.target.matches(':focus-visible')) return; } catch (err) { return; }
      cancelGlide();
      a.scrollIntoView({ inline: 'center', block: 'nearest', behavior: reduced.matches ? 'auto' : 'smooth' });
    });

    strip.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', schedule);
    if ('ResizeObserver' in window) new ResizeObserver(schedule).observe(box);
    if ('MutationObserver' in window) {
      new MutationObserver(schedule).observe(strip, { subtree: true, childList: true, attributes: true, attributeFilter: ['hidden'] });
    }
    measure();
  }

  Array.prototype.forEach.call(document.querySelectorAll('.album-carousel'), init);
})();
