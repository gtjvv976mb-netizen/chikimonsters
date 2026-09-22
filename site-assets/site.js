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
  const worldTrack = document.querySelector(".world-track");
  const worldStage = document.querySelector(".world-stage");
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
  const beats = [hero, ...journey.querySelectorAll(".journey-beat")];
  const journeyVideo = worldStage.querySelector(".world-journey");
  const journeyPoster = worldStage.querySelector(".world-poster");

  function syncSceneMode() {
    document.documentElement.classList.toggle("scene-static", !motionEnabled() || saveData);
  }

  function syncMotionToggle() {
    motionToggle.hidden = !reduceMotion.matches || saveData;
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

  // ONE video, ONE world. The whole page is a single 45-second first-person walk
  // through Chikoria (vista -> river -> Wicked Temple -> Chikiseum), and the scroll
  // position is the playhead: the top of the page is the first frame, the end of
  // the last chapter is the last frame. There are no per-chapter scenes and no
  // doorway clips any more — those morphed one painting into the next, and the
  // morph is where islands, creatures and terrain used to appear and vanish.
  //
  // The clip is encoded with a keyframe every six frames so a seek decodes at
  // most six frames, and one seek is in flight at a time.
  let scrollFrame = 0;
  let beatTops = [];
  let trackEnd = 0;
  let journeyReady = false;
  let journeyPrimed = false;
  const JOURNEY_LENGTH = 45;
  // Scroll anchors -> seconds. The stage is pinned until chapter 04's heading
  // reaches the top of the viewport, so that is where the walk arrives at the
  // Chikiseum gate; 02 (riverside) opens on the descent to the river and 03 on
  // the temple steps. The hero and chapter 01 share the first shot.
  const SHOT_TIMES = [0, 15, 30, JOURNEY_LENGTH];

  function journeySource() {
    return wideScreen.matches ? journeyVideo.dataset.src : (journeyVideo.dataset.srcPhone || journeyVideo.dataset.src);
  }
  function loadJourney() {
    if (!canMoveScene() || journeyVideo.hasAttribute("src")) return;
    journeyVideo.src = journeySource();
    journeyVideo.load();
  }
  journeyVideo.addEventListener("loadedmetadata", () => {
    // iOS decodes a paused video's frames only after it has been "played" once.
    // A muted, inline play() is allowed without a gesture; it is paused at once.
    if (!journeyPrimed) {
      journeyPrimed = true;
      const p = journeyVideo.play();
      if (p && p.then) p.then(() => journeyVideo.pause()).catch(() => {});
    }
    scheduleScroll();
  });
  journeyVideo.addEventListener("loadeddata", () => {
    journeyReady = true;
    worldStage.classList.add("is-journey-ready");
    scheduleScroll();
  });
  journeyVideo.addEventListener("seeked", scheduleScroll);
  journeyVideo.addEventListener("error", () => {
    journeyReady = false;
    worldStage.classList.remove("is-journey-ready");   // the poster (first frame) stays
  });

  function measureRail() {
    beatTops = beats.map((beat) => beat.getBoundingClientRect().top + window.scrollY);
    trackEnd = worldTrack.getBoundingClientRect().bottom + window.scrollY;
    scheduleScroll();
  }

  // Piecewise-linear map from scroll position to seconds through the anchors.
  function journeyTime(y) {
    const viewport = window.innerHeight;
    const anchors = [0, beatTops[2], beatTops[3], Math.min(beatTops[4], trackEnd - viewport)].map((v, i, arr) =>
      Math.max(v || 0, i ? arr[i - 1] + 1 : 0));
    if (y <= anchors[0]) return SHOT_TIMES[0];
    for (let i = 1; i < anchors.length; i += 1) {
      if (y <= anchors[i]) {
        const f = (y - anchors[i - 1]) / Math.max(1, anchors[i] - anchors[i - 1]);
        return SHOT_TIMES[i - 1] + f * (SHOT_TIMES[i] - SHOT_TIMES[i - 1]);
      }
    }
    return JOURNEY_LENGTH;
  }

  function renderScroll() {
    scrollFrame = 0;
    const y = window.scrollY;
    const viewport = window.innerHeight;
    header.classList.toggle("is-scrolled", y > 30);
    if (!canMoveScene()) return;
    loadJourney();
    if (y > trackEnd) return;                   // the stage has scrolled away
    const duration = Number.isFinite(journeyVideo.duration) && journeyVideo.duration > 1 ? journeyVideo.duration : JOURNEY_LENGTH;
    const target = Math.min(duration - 0.05, journeyTime(y) * (duration / JOURNEY_LENGTH));
    if (journeyVideo.readyState >= 1 && !journeyVideo.seeking && Math.abs(journeyVideo.currentTime - target) > 1 / 48) {
      journeyVideo.currentTime = target;
    }
    const progress = clamp((y - beatTops[1]) / Math.max(1, trackEnd - viewport - beatTops[1]));
    worldStage.style.setProperty("--journey-progress", `${(progress * 100).toFixed(1)}%`);
  }
  function scheduleScroll() {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(renderScroll);
  }
  function clearSceneTransforms() {
    worldStage.style.removeProperty("--journey-progress");
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
  measureRail();
  renderScroll();
  window.addEventListener("scroll", scheduleScroll, { passive: true });
  window.addEventListener("resize", measureRail, { passive: true });
  if ("ResizeObserver" in window) new ResizeObserver(measureRail).observe(worldTrack);
  if (document.fonts?.ready) document.fonts.ready.then(measureRail);
  document.addEventListener("visibilitychange", scheduleScroll);
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
    if (document.hidden) introVideo.pause();
    else scheduleScroll();
  });
})();
