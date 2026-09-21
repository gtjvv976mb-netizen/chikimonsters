(() => {
  "use strict";

  document.documentElement.classList.add("has-js");
  const header = document.querySelector(".site-header");
  const menu = document.querySelector(".menu-toggle");
  const links = document.getElementById("nav-links");
  const dialog = document.getElementById("intro-dialog");
  const introVideo = document.getElementById("intro-video");
  const watch = document.getElementById("watch-intro");
  const hero = document.querySelector(".hero");
  const journey = document.querySelector(".journey");
  const motionToggle = document.getElementById("motion-toggle");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const wideScreen = window.matchMedia("(min-width: 761px)");
  const saveData = Boolean(navigator.connection && navigator.connection.saveData);
  let motionOptIn = false;
  const motionEnabled = () => !reduceMotion.matches || motionOptIn;
  const canMoveScene = () => motionEnabled() && !saveData && !document.hidden;
  const clamp = (value, low = 0, high = 1) => Math.max(low, Math.min(high, value));
  const smoothstep = (value) => {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  };
  const scenes = Array.from(journey.querySelectorAll(".journey-scene"));
  const firstBeat = journey.querySelector(".journey-beat");
  const heroAmbient = hero.querySelector(".hero-motion");
  const sceneAmbients = scenes.map((scene) => scene.querySelector(".scene-motion"));
  const allAmbients = [heroAmbient, ...sceneAmbients];
  const canPlayAmbient = () => wideScreen.matches && canMoveScene();
  let activeAmbient = null;
  let pendingAmbient = null;
  let ambientTimer = 0;

  // Sources stay in data-src until the visitor reaches that scene. A failed or
  // blocked clip simply leaves the complete painted scene in place.
  for (const video of allAmbients) {
    video.addEventListener("loadeddata", () => video.classList.add("is-ready"));
    video.addEventListener("playing", () => {
      video.dataset.requested = "";
      video.classList.add("is-active");
    });
    video.addEventListener("pause", () => video.classList.remove("is-active"));
    video.addEventListener("error", () => {
      video.dataset.failed = "1";
      video.dataset.requested = "";
      video.classList.remove("is-ready", "is-active");
      video.pause();
      video.removeAttribute("src");
      if (activeAmbient === video) activeAmbient = null;
      if (pendingAmbient === video) pendingAmbient = null;
    });
  }

  function startAmbient(video) {
    if (!video || !canPlayAmbient() || video.dataset.failed || video.dataset.blocked) return;
    activeAmbient = video;
    if (!video.hasAttribute("src")) {
      video.src = video.dataset.src;
      video.load();
    }
    if (video.paused && !video.dataset.requested) {
      video.dataset.requested = "1";
      video.play().catch(() => {
        video.dataset.requested = "";
        video.dataset.blocked = "1";
        video.classList.remove("is-active");
      });
    }
  }

  function useAmbient(next) {
    if (!canPlayAmbient()) next = null;
    if (next && (next.dataset.failed || next.dataset.blocked)) next = null;
    if (pendingAmbient === next) {
      if (next && activeAmbient === next && next.paused) startAmbient(next);
      return;
    }
    clearTimeout(ambientTimer);
    pendingAmbient = next;
    if (activeAmbient && activeAmbient !== next) {
      activeAmbient.pause();
      activeAmbient.classList.remove("is-active");
      activeAmbient.dataset.requested = "";
      activeAmbient = null;
    }
    // A visitor flying past a chapter never starts downloading its clip.
    if (next) ambientTimer = setTimeout(() => {
      if (pendingAmbient === next) startAmbient(next);
    }, 240);
  }

  function syncSceneMode() {
    document.documentElement.classList.toggle("scene-static", !motionEnabled() || saveData);
  }

  function syncMotionToggle() {
    motionToggle.hidden = !reduceMotion.matches;
    motionToggle.setAttribute("aria-pressed", String(motionOptIn));
    motionToggle.setAttribute("aria-label", `${motionOptIn ? "Turn off" : "Turn on"} cinematic scroll motion`);
    motionToggle.querySelector(".cinematic-toggle-state").textContent = motionOptIn ? "On" : "Off";
  }
  syncMotionToggle();
  syncSceneMode();

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

  // Each painted scene already contains its creatures. As the viewport travels
  // through four chapters, zoom the current painting toward its focal point
  // and reveal the next one through a scroll-linked crossfade. No separate
  // Chikimon layer can drift away from its ground, light, or shadow.
  let scrollFrame = 0;
  function renderScroll() {
    scrollFrame = 0;
    header.classList.toggle("is-scrolled", window.scrollY > 30);

    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom > 0 && heroRect.top < window.innerHeight && canMoveScene()) {
      const heroProgress = clamp(-heroRect.top / Math.max(1, heroRect.height));
      const heroZoom = 1.045 + (wideScreen.matches ? 0.27 : 0.15) * heroProgress;
      hero.style.setProperty("--hero-scale", heroZoom.toFixed(4));
    }

    const journeyRect = journey.getBoundingClientRect();
    let dominantScene = 0;
    if (journeyRect.bottom > 0 && journeyRect.top < window.innerHeight && canMoveScene()) {
      const viewport = window.innerHeight;
      const travelled = Math.max(0, -journeyRect.top);
      const chapterHeight = Math.max(1, firstBeat.offsetHeight);
      const position = clamp((travelled + viewport * 0.08) / chapterHeight, 0, 3.08);
      const zoomRange = wideScreen.matches ? 0.34 : 0.18;
      let highestOpacity = -1;

      for (let index = 0; index < scenes.length; index += 1) {
        // A shared .36-chapter window keeps both image layers complementary:
        // a visitor can stop mid-scroll without seeing a black flash or jump.
        const entering = index === 0 ? 1 : smoothstep((position - (index - 0.38)) / 0.36);
        const exiting = index === scenes.length - 1 ? 1 : 1 - smoothstep((position - (index + 0.62)) / 0.36);
        const opacity = entering * exiting;
        if (opacity > highestOpacity) {
          highestOpacity = opacity;
          dominantScene = index;
        }
        const local = clamp(position - index + 0.08);
        scenes[index].style.opacity = opacity.toFixed(3);
        scenes[index].style.setProperty("--scene-scale", (1.045 + local * zoomRange).toFixed(4));
      }
      const progress = clamp(travelled / Math.max(1, journeyRect.height - viewport));
      journey.style.setProperty("--journey-near-y", `${(progress * (wideScreen.matches ? 42 : 18)).toFixed(1)}px`);
      journey.style.setProperty("--journey-progress", `${(progress * 100).toFixed(1)}%`);
    }
    const showHero = heroRect.bottom > window.innerHeight * 0.45 && heroRect.top < window.innerHeight;
    const showJourney = journeyRect.bottom > 0 && journeyRect.top < window.innerHeight;
    useAmbient(canPlayAmbient() && showHero ? heroAmbient : canPlayAmbient() && showJourney ? sceneAmbients[dominantScene] : null);
  }
  function scheduleScroll() {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(renderScroll);
  }
  function clearSceneTransforms() {
    hero.style.removeProperty("--hero-scale");
    for (const scene of scenes) {
      scene.style.removeProperty("--scene-scale");
      scene.style.removeProperty("opacity");
    }
    for (const property of ["--journey-near-y", "--journey-progress"]) journey.style.removeProperty(property);
  }
  motionToggle.addEventListener("click", () => {
    motionOptIn = !motionOptIn;
    document.documentElement.classList.toggle("motion-opt-in", motionOptIn);
    syncMotionToggle();
    syncSceneMode();
    if (!motionEnabled()) clearSceneTransforms();
    // The control is in the hero, so the stage can switch before the next paint.
    renderScroll();
  });
  renderScroll();
  window.addEventListener("scroll", scheduleScroll, { passive: true });
  window.addEventListener("resize", scheduleScroll, { passive: true });
  reduceMotion.addEventListener("change", () => {
    motionOptIn = false;
    document.documentElement.classList.remove("motion-opt-in");
    syncMotionToggle();
    syncSceneMode();
    if (!motionEnabled()) clearSceneTransforms();
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
        behavior: motionEnabled() ? "smooth" : "auto",
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
    if (document.hidden) {
      introVideo.pause();
      useAmbient(null);
    } else scheduleScroll();
  });
})();
