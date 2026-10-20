// Minimal scroll-snap carousel controller — no dependency, works for any
// number of .carousel instances on the page. The scrolling itself is
// native CSS (scroll-snap-type); this just wires up arrows/dots on top.
document.querySelectorAll('.carousel').forEach(function (carousel) {
  var track = carousel.querySelector('.carousel-track');
  var items = Array.from(track.children);
  var prevBtn = carousel.querySelector('.carousel-btn.prev');
  var nextBtn = carousel.querySelector('.carousel-btn.next');
  var dotsWrap = carousel.querySelector('.carousel-dots');

  var dots = items.map(function (item, i) {
    var dot = document.createElement('button');
    dot.className = 'carousel-dot';
    dot.setAttribute('aria-label', 'Go to slide ' + (i + 1));
    dot.addEventListener('click', function () { goTo(i); });
    dotsWrap.appendChild(dot);
    return dot;
  });

  function currentIndex() {
    var closest = 0;
    var closestDist = Infinity;
    items.forEach(function (item, i) {
      var dist = Math.abs(targetScrollLeft(item) - track.scrollLeft);
      if (dist < closestDist) { closestDist = dist; closest = i; }
    });
    return closest;
  }

  function targetScrollLeft(item) {
    return track.scrollLeft + item.getBoundingClientRect().left - track.getBoundingClientRect().left;
  }

  function goTo(i) {
    track.scrollTo({
      left: targetScrollLeft(items[i]),
      behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'
    });
  }

  function update() {
    var i = currentIndex();
    dots.forEach(function (dot, di) {
      dot.classList.toggle('active', di === i);
      if (di === i) dot.setAttribute('aria-current', 'true');
      else dot.removeAttribute('aria-current');
    });
    prevBtn.disabled = i === 0;
    nextBtn.disabled = i === items.length - 1;
  }

  prevBtn.addEventListener('click', function () { goTo(Math.max(0, currentIndex() - 1)); });
  nextBtn.addEventListener('click', function () { goTo(Math.min(items.length - 1, currentIndex() + 1)); });
  track.addEventListener('scroll', function () { window.requestAnimationFrame(update); }, { passive: true });
  track.addEventListener('keydown', function (event) {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    goTo(Math.max(0, Math.min(items.length - 1, currentIndex() + (event.key === 'ArrowRight' ? 1 : -1))));
  });
  update();
});
