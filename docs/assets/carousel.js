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
      var dist = Math.abs(item.offsetLeft - track.scrollLeft);
      if (dist < closestDist) { closestDist = dist; closest = i; }
    });
    return closest;
  }

  function goTo(i) {
    items[i].scrollIntoView({ behavior: 'smooth', inline: 'start', block: 'nearest' });
  }

  function update() {
    var i = currentIndex();
    dots.forEach(function (dot, di) { dot.classList.toggle('active', di === i); });
    prevBtn.disabled = i === 0;
    nextBtn.disabled = i === items.length - 1;
  }

  prevBtn.addEventListener('click', function () { goTo(Math.max(0, currentIndex() - 1)); });
  nextBtn.addEventListener('click', function () { goTo(Math.min(items.length - 1, currentIndex() + 1)); });
  track.addEventListener('scroll', function () { window.requestAnimationFrame(update); }, { passive: true });
  update();
});
