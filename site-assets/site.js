(() => {
  "use strict";

  const header = document.querySelector(".site-header");
  const menu = document.querySelector(".menu-toggle");
  const links = document.getElementById("nav-links");
  const dialog = document.getElementById("intro-dialog");
  const introVideo = document.getElementById("intro-video");
  const watch = document.getElementById("watch-intro");
  const hero = document.querySelector(".hero");
  const journey = document.querySelector(".journey");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const wideScreen = window.matchMedia("(min-width: 761px)");
  const saveData = Boolean(navigator.connection && navigator.connection.saveData);
  const canMoveScene = () => wideScreen.matches && !reduceMotion.matches && !saveData && !document.hidden;

  document.getElementById("year").textContent = String(new Date().getFullYear());

  function setMenu(open) {
    menu.setAttribute("aria-expanded", String(open));
    menu.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    links.classList.toggle("is-open", open);
    header.classList.toggle("menu-open", open);
  }
  menu.addEventListener("click", () => setMenu(menu.getAttribute("aria-expanded") !== "true"));
  links.addEventListener("click", (event) => {
    if (event.target.closest("a")) setMenu(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setMenu(false);
  });
  document.addEventListener("click", (event) => {
    if (!header.contains(event.target)) setMenu(false);
  });

  // The homepage is the title screen. Entering through it skips the duplicate title in Godot.
  for (const link of document.querySelectorAll("a.enter-game")) {
    link.addEventListener("click", () => {
      try {
        sessionStorage.setItem("realm-hero-done", "1");
      } catch (_) {
        /* Private browsing can disallow session storage. */
      }
    });
  }

  function closeIntro() {
    introVideo.pause();
    introVideo.removeAttribute("src");
    introVideo.load();
    if (dialog.open) dialog.close();
  }
  watch.addEventListener("click", () => {
    dialog.showModal();
    introVideo.src = "/intro.mp4";
    introVideo.play().catch(() => {
      /* Native controls remain available when autoplay is denied. */
    });
  });
  dialog.querySelector(".intro-close").addEventListener("click", closeIntro);
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    closeIntro();
  });
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) closeIntro();
  });

  // Enhancement only: all sections remain readable without JS or motion support.
  if ("IntersectionObserver" in window && !reduceMotion.matches) {
    document.documentElement.classList.add("motion-ready");
    const reveals = new IntersectionObserver(
      (entries, observer) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -30px 0px" },
    );
    document.querySelectorAll(".reveal").forEach((element) => reveals.observe(element));
  }

  // Four painted scene planes create a camera-like scroll journey. One passive
  // scroll listener and one rAF update; only compositor-friendly transforms move.
  let scrollFrame = 0;
  function renderScroll() {
    scrollFrame = 0;
    header.classList.toggle("is-scrolled", window.scrollY > 30);

    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom > 0 && heroRect.top < window.innerHeight && canMoveScene()) {
      const travel = Math.max(0, Math.min(heroRect.height, -heroRect.top));
      hero.style.setProperty("--back-y", `${(-travel * 0.11).toFixed(1)}px`);
      hero.style.setProperty("--mid-y", `${(-travel * 0.20).toFixed(1)}px`);
      hero.style.setProperty("--front-y", `${(-travel * 0.30).toFixed(1)}px`);
      hero.style.setProperty("--cast-y", `${(-travel * 0.27).toFixed(1)}px`);
      for (const sprite of hero.querySelectorAll(".hero-creature[data-depth]")) {
        sprite.style.setProperty("--sprite-y", `${(travel * Number(sprite.dataset.depth) * 0.10).toFixed(1)}px`);
      }
    }

    const journeyRect = journey.getBoundingClientRect();
    if (journeyRect.bottom > 0 && journeyRect.top < window.innerHeight) {
      const viewport = window.innerHeight;
      const travelled = Math.max(0, -journeyRect.top);
      const active = Math.min(3, Math.floor((travelled + viewport * 0.5) / viewport));
      journey.dataset.scene = ["realm", "gathering", "temple", "arena"][active];
      if (canMoveScene()) {
        const progress = Math.max(0, Math.min(1, travelled / Math.max(1, journeyRect.height - viewport)));
        journey.style.setProperty("--journey-y", `${(-progress * 54).toFixed(1)}px`);
        journey.style.setProperty("--journey-near-y", `${(progress * 42).toFixed(1)}px`);
        journey.style.setProperty("--journey-progress", `${(progress * 100).toFixed(1)}%`);
      }
    }
  }
  function scheduleScroll() {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(renderScroll);
  }
  renderScroll();
  window.addEventListener("scroll", scheduleScroll, { passive: true });
  window.addEventListener("resize", scheduleScroll, { passive: true });
  reduceMotion.addEventListener("change", () => {
    if (reduceMotion.matches) {
      for (const property of ["--back-y", "--mid-y", "--front-y", "--cast-y"]) hero.style.removeProperty(property);
      for (const sprite of hero.querySelectorAll(".hero-creature[data-depth]")) sprite.style.removeProperty("--sprite-y");
      journey.style.removeProperty("--journey-y");
      journey.style.removeProperty("--journey-near-y");
    }
    scheduleScroll();
  });

  // The extended 2D roster is a native scroll-snap strip. Buttons are a
  // desktop enhancement; swiping and keyboard scrolling work without JS.
  const roster = document.getElementById("roster-track");
  const rosterControls = document.querySelector(".roster-controls");
  if (roster && rosterControls) {
    const previous = rosterControls.querySelector('[data-roster-dir="-1"]');
    const next = rosterControls.querySelector('[data-roster-dir="1"]');
    function moveRoster(direction) {
      roster.scrollBy({
        left: direction * roster.clientWidth * .82,
        behavior: reduceMotion.matches ? "auto" : "smooth",
      });
    }
    function updateRosterControls() {
      const maxScroll = Math.max(0, roster.scrollWidth - roster.clientWidth);
      rosterControls.hidden = maxScroll < 2;
      previous.disabled = roster.scrollLeft < 3;
      next.disabled = roster.scrollLeft > maxScroll - 3;
    }
    for (const button of [previous, next]) {
      button.addEventListener("click", () => moveRoster(Number(button.dataset.rosterDir)));
    }
    roster.addEventListener("keydown", (event) => {
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        moveRoster(event.key === "ArrowRight" ? 1 : -1);
      }
    });
    roster.addEventListener("scroll", updateRosterControls, { passive: true });
    window.addEventListener("resize", updateRosterControls, { passive: true });
    requestAnimationFrame(updateRosterControls);
  }

  // Gameplay footage is intentionally not wired yet. The four static preview
  // cards in index.html carry data-video-slot IDs (exploration, gathering,
  // wicked-temple, chikiseum). When verified footage is available, add a
  // poster and a click-to-play video for each matching slot; never autoplay.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) introVideo.pause();
  });
})();
