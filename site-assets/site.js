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
  const travelVideo = worldStage.querySelector(".world-travel");
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
  const scenes = Array.from(worldStage.querySelectorAll(".journey-scene"));
  const beats = [hero, ...journey.querySelectorAll(".journey-beat")];
  const sceneAmbients = scenes.map((scene) => scene.querySelector(".scene-motion"));
  const allAmbients = sceneAmbients;
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
    // A clip without `loop` is one take of a camera move: it plays once and
    // then HOLDS on its last frame. The browser fires "pause" at the end too,
    // and hiding the clip there would snap the world back to its first frame,
    // which is the cut the take exists to avoid.
    video.addEventListener("pause", () => {
      if (!video.ended) video.classList.remove("is-active");
    });
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

  // One camera rail runs behind the hero and every chapter. The creature,
  // contact shadow, and ground stay on the same painted plane. At a doorway,
  // an opaque threshold hides the scene swap instead of ghosting two casts.
  let scrollFrame = 0;
  let beatTops = [];
  let trackEnd = 0;
  // These clips are scrubbed by scroll position, not played. Every seek decodes
  // from the previous keyframe, so they are encoded with a keyframe every four
  // frames; the standard encode (one every 29) made each scroll step a 29-frame
  // decode and was the main source of stutter through the doorways.
  const transitionClips = [
    "/site-assets/world-travel-realm-gathering-seek.mp4",
    "/site-assets/world-travel-gathering-temple-seek.mp4",
    "/site-assets/world-travel-temple-arena-seek.mp4",
  ];
  let travelIndex = -1;
  const failedTravel = new Set();
  travelVideo.addEventListener("loadeddata", scheduleScroll);
  travelVideo.addEventListener("seeked", scheduleScroll);
  travelVideo.addEventListener("error", () => {
    if (travelIndex >= 0) failedTravel.add(travelIndex);
    worldStage.style.setProperty("--travel-opacity", "0");
    scheduleScroll();
  });

  function measureRail() {
    beatTops = beats.map((beat) => beat.getBoundingClientRect().top + window.scrollY);
    trackEnd = worldTrack.getBoundingClientRect().bottom + window.scrollY;
    scheduleScroll();
  }

  // Style writes are skipped when nothing changed: the three idle scenes are
  // reset every frame, and rewriting five custom properties on each of them
  // forced a style recalculation of the whole stage on every scroll step.
  const cameraMemo = new WeakMap();
  function setCamera(scene, opacity, scale, x, y, tilt, activeClass = "") {
    const key = `${opacity.toFixed(3)}|${scale.toFixed(4)}|${x.toFixed(1)}|${y.toFixed(1)}|${tilt.toFixed(2)}|${activeClass}`;
    if (cameraMemo.get(scene) === key) return;
    cameraMemo.set(scene, key);
    scene.style.setProperty("--scene-opacity", opacity.toFixed(3));
    scene.style.setProperty("--camera-scale", scale.toFixed(4));
    scene.style.setProperty("--camera-x", `${x.toFixed(1)}px`);
    scene.style.setProperty("--camera-y", `${y.toFixed(1)}px`);
    scene.style.setProperty("--camera-tilt", `${tilt.toFixed(2)}deg`);
    scene.classList.toggle("is-camera-active", activeClass === "active");
    scene.classList.toggle("is-camera-next", activeClass === "next");
  }

  function syncTravel(index, progress) {
    const source = transitionClips[index];
    if (!source || failedTravel.has(index) || !canPlayAmbient()) {
      worldStage.style.setProperty("--travel-opacity", "0");
      return false;
    }
    if (travelIndex !== index) {
      travelIndex = index;
      travelVideo.src = source;
      travelVideo.load();
    }
    if (travelVideo.readyState < 2) {
      worldStage.style.setProperty("--travel-opacity", "0");
      return false;
    }
    const duration = Number.isFinite(travelVideo.duration) ? travelVideo.duration : 5;
    const targetTime = clamp(progress) * Math.max(0, duration - 0.04);
    // One seek in flight at a time. Piling a new seek onto every frame while the
    // decoder was still on the last one is what made the doorway clips judder;
    // the "seeked" listener above schedules the catch-up frame.
    if (!travelVideo.seeking && Math.abs(travelVideo.currentTime - targetTime) > 0.055) travelVideo.currentTime = targetTime;
    const fade = Math.min(smoothstep(progress / .075), smoothstep((1 - progress) / .075));
    worldStage.style.setProperty("--travel-opacity", fade.toFixed(3));
    return true;
  }

  function prepareTravel(index) {
    const source = transitionClips[index];
    if (!source || failedTravel.has(index) || !canPlayAmbient() || travelIndex === index) return;
    travelIndex = index;
    travelVideo.src = source;
    travelVideo.load();
  }

  function renderScroll() {
    scrollFrame = 0;
    header.classList.toggle("is-scrolled", window.scrollY > 30);
    if (!canMoveScene() || window.scrollY + window.innerHeight < beatTops[0] || window.scrollY > trackEnd) {
      useAmbient(null);
      worldStage.style.setProperty("--travel-opacity", "0");
      return;
    }

    const y = window.scrollY;
    const viewport = window.innerHeight;
    const width = window.innerWidth;
    const wide = wideScreen.matches;
    const lead = wide ? .76 : .68;
    const tail = wide ? .24 : .20;
    let sceneIndex = 0;
    let transitionIndex = -1;
    let transitionProgress = 0;
    for (let index = 0; index < scenes.length - 1; index += 1) {
      const boundary = beatTops[index + 2];
      const start = boundary - viewport * lead;
      const end = boundary - viewport * tail;
      if (y >= start && y <= end) {
        transitionIndex = index;
        transitionProgress = smoothstep((y - start) / Math.max(1, end - start));
        break;
      }
      if (y > end) sceneIndex = index + 1;
    }

    for (const scene of scenes) setCamera(scene, 0, 1.045, 0, 0, 0);
    if (transitionIndex >= 0) {
      const t = transitionProgress;
      const outgoing = scenes[transitionIndex];
      const incoming = scenes[transitionIndex + 1];
      const move = wide ? 1 : .48;
      const forward = smoothstep(t);
      const switchScene = t < .5 ? 0 : 1;
      // No tilt on phones: a rotateX of even a fraction of a degree is a
      // perspective transform, and a full-screen 3x-density scene under one is
      // re-rasterised on every scroll step instead of just moved by the GPU.
      setCamera(outgoing, 1 - switchScene, 1.17 + forward * (wide ? .62 : .26),
        -forward * width * .07 * move, -forward * viewport * .055 * move,
        wide ? forward * 2.8 : 0, "active");
      setCamera(incoming, switchScene, (wide ? 1.31 : 1.13) - forward * (wide ? .22 : .09),
        (1 - forward) * width * .045 * move, (1 - forward) * viewport * .035 * move,
        wide ? -(1 - forward) * 1.8 : 0, "next");
      const clipVisible = syncTravel(transitionIndex, t);
      const distanceFromMiddle = 1 - Math.abs(t * 2 - 1);
      const threshold = clipVisible ? .12 * smoothstep(distanceFromMiddle) : smoothstep(distanceFromMiddle);
      worldStage.style.setProperty("--threshold-opacity", threshold.toFixed(3));
      useAmbient(null);
      sceneIndex = t < .5 ? transitionIndex : transitionIndex + 1;
    } else {
      worldStage.style.setProperty("--travel-opacity", "0");
      worldStage.style.setProperty("--threshold-opacity", "0");
      const segmentStart = sceneIndex === 0 ? beatTops[0] : beatTops[sceneIndex + 1] - viewport * tail;
      const segmentEnd = sceneIndex === scenes.length - 1 ? trackEnd - viewport : beatTops[sceneIndex + 2] - viewport * lead;
      const local = clamp((y - segmentStart) / Math.max(1, segmentEnd - segmentStart));
      const travel = smoothstep(local);
      setCamera(scenes[sceneIndex], 1, 1.045 + travel * (wide ? .125 : .055),
        -travel * width * (wide ? .034 : .012), -travel * viewport * (wide ? .028 : .012),
        wide ? travel * 1.1 : 0, "active");
      const stageVisible = y + viewport > beatTops[0] && y < trackEnd - viewport * .25;
      useAmbient(canPlayAmbient() && stageVisible ? sceneAmbients[sceneIndex] : null);
      if (sceneIndex < scenes.length - 1 && y > segmentEnd - viewport * .5) prepareTravel(sceneIndex);
    }
    const progress = clamp((y - beatTops[1]) / Math.max(1, trackEnd - viewport - beatTops[1]));
    worldStage.style.setProperty("--journey-progress", `${(progress * 100).toFixed(1)}%`);
  }
  function scheduleScroll() {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(renderScroll);
  }
  function clearSceneTransforms() {
    for (const scene of scenes) {
      cameraMemo.delete(scene);
      for (const property of ["--scene-opacity", "--camera-scale", "--camera-x", "--camera-y", "--camera-tilt"]) scene.style.removeProperty(property);
      scene.classList.remove("is-camera-active", "is-camera-next");
    }
    worldStage.style.removeProperty("--threshold-opacity");
    worldStage.style.removeProperty("--journey-progress");
    worldStage.style.removeProperty("--travel-opacity");
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
