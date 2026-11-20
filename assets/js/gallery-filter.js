// The Gallery page's category chips. Chips are toggles that add up (none on = every album); the state is mirrored to
// ?category=a,b so a filtered view can be linked, and it is cleared first when a link targets an album it hides.
// The bar ships `hidden` and is revealed here, so without JS every album is simply listed.
// The pure part (parse, visible) is exported for tests/gallery-filter.test.js.
(function () {
  // "?category=lab-life,demos" -> ["lab-life", "demos"], dropping anything that is not a known category.
  function parse(search, known) {
    var m = /[?&]category=([^&]*)/.exec(search || '');
    if (!m) return [];
    var seen = {};
    return decodeURIComponent(m[1]).split(',').filter(function (id) {
      if (!id || seen[id] || known.indexOf(id) < 0) return false;
      seen[id] = true;
      return true;
    });
  }

  // One boolean per album: shown when nothing is selected or its category is.
  function visible(categories, selected) {
    return categories.map(function (c) { return selected.length === 0 || selected.indexOf(c) >= 0; });
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = { parse: parse, visible: visible };
  if (typeof document === 'undefined') return;

  var bar = document.querySelector('.gallery-filters');
  if (!bar) return;
  var chips = Array.prototype.slice.call(bar.querySelectorAll('.chip[data-filter="category"]'));
  var clear = bar.querySelector('.gallery-filters__clear');
  var status = bar.querySelector('.gallery-filters__status');
  var albums = Array.prototype.slice.call(document.querySelectorAll('.album[data-category]'));
  var years = Array.prototype.slice.call(document.querySelectorAll('.gallery-year'));
  var known = chips.map(function (c) { return c.dataset.value; });
  var selected = parse(window.location.search, known);

  function apply() {
    var shown = visible(albums.map(function (a) { return a.dataset.category; }), selected);
    albums.forEach(function (a, i) { a.hidden = !shown[i]; });
    years.forEach(function (y) { y.hidden = !y.querySelector('.album:not([hidden])'); });
    chips.forEach(function (c) { c.setAttribute('aria-pressed', selected.indexOf(c.dataset.value) >= 0 ? 'true' : 'false'); });
    var n = shown.filter(Boolean).length;
    var filtering = selected.length > 0;
    clear.hidden = !filtering;
    status.textContent = filtering ? 'Showing ' + n + ' of ' + albums.length + ' albums' : '';
    var query = filtering ? '?category=' + selected.map(encodeURIComponent).join(',') : '';
    try { window.history.replaceState(null, '', window.location.pathname + query + window.location.hash); } catch (e) { /* file:// */ }
  }

  // A link to an album the filter hides clears the filter, then scrolls to it.
  function reveal() {
    var id = decodeURIComponent(window.location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (target && target.closest('[hidden]') && selected.length) {
      selected = [];
      apply();
      target.scrollIntoView();
    }
  }

  chips.forEach(function (chip) {
    chip.addEventListener('click', function () {
      var id = chip.dataset.value;
      var at = selected.indexOf(id);
      if (at >= 0) selected.splice(at, 1); else selected.push(id);
      apply();
    });
  });
  clear.addEventListener('click', function () { selected = []; apply(); });
  window.addEventListener('hashchange', reveal);

  bar.hidden = false;
  apply();
  reveal();
})();
