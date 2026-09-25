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
  const wideScreen = window.matchMedia("(min-width: 761px)");
  // The cinematic scroll motion is the page. It is always on: there is no
  // toggle, and neither reduced-motion nor data-saver settings switch it off.
  const motionEnabled = () => true;
  const canMoveScene = () => !document.hidden;
  const clamp = (value, low = 0, high = 1) => Math.max(low, Math.min(high, value));
  const smoothstep = (value) => {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  };
  const beats = [hero, ...journey.querySelectorAll(".journey-beat")];
  const journeyVideo = worldStage.querySelector(".world-journey");
  const journeyPoster = worldStage.querySelector(".world-poster");

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

  // Reveals run on the same scroll frame as the journey, so they can never lag
  // behind it or miss their cue: on every frame, anything whose top has entered
  // the lower 94% of the viewport is revealed, once. (An IntersectionObserver
  // used to do this asynchronously, and could fire late or not at all for
  // content that moved under a tab switch or a resize.)
  document.documentElement.classList.add("motion-ready");
  const reveals = [...document.querySelectorAll(".reveal")];
  function revealInView() {
    if (!reveals.length) return;
    const limit = window.innerHeight * 0.94;
    for (let i = reveals.length - 1; i >= 0; i -= 1) {
      const rect = reveals[i].getBoundingClientRect();
      if (rect.top < limit && rect.bottom > 0) {
        reveals[i].classList.add("is-visible");
        reveals.splice(i, 1);
      }
    }
  }

  // ONE picture, ONE video. The whole page is a single first-person walk through
  // one painting of Chikoria (vista -> river and bridge -> Wicked Temple ->
  // Chikiseum -> through its gate into the light), and the scroll position is the
  // playhead: the top of the page is the first frame, the end of the last chapter
  // is the last frame. Every shot of the walk is pinned to keyframes cut from that
  // one painting, with Firix, Bamboran and Rivaros the only Chikimons in it, so
  // the camera moves into the scene and each place stays the place.
  //
  // The clip is encoded with a keyframe every six frames so a seek decodes at
  // most six frames, and one seek is in flight at a time.
  let scrollFrame = 0;
  let beatTops = [];
  let trackEnd = 0;
  let journeyReady = false;
  let journeyPrimed = false;
  let journeyRetries = 0;
  let seekStartedAt = 0;
  const JOURNEY_LENGTH = 51.625;
  // Scroll anchors -> seconds, one stretch of the walk per stretch of page. Each
  // chapter's heading reaches the top of the viewport as the walk arrives at its
  // place: the hero and 01 walk down the path as Firix trots up to meet you, 02
  // lands on the river bank beside Rivaros (15.06 s), 03 at the foot of the Wicked
  // Temple (28.44 s), and the road climbs to the Chikiseum and through its gate,
  // into the light as 04 lands. 02 and 03 each land inside the first whole frame
  // after a dissolve (frames 361 and 682 at 24 fps), never on a blend of two shots.
  const SHOT_TIMES = [0, 6, 15.06, 28.44, JOURNEY_LENGTH];

  function journeySource() {
    return wideScreen.matches ? journeyVideo.dataset.src : (journeyVideo.dataset.srcPhone || journeyVideo.dataset.src);
  }
  function loadJourney() {
    if (!canMoveScene() || journeyVideo.hasAttribute("src")) return;
    journeyVideo.src = journeySource();
    journeyVideo.load();
  }
  // iOS (and some Android browsers) decode a paused video's frames only after
  // it has been "played" once. A muted, inline play() is allowed without a
  // gesture and is paused at once. If the browser refuses (Low Power Mode, a
  // strict autoplay policy), the same priming is retried on the first
  // interaction of any kind, so the walk is never left unplayed.
  function primeJourney() {
    if (journeyPrimed || journeyVideo.readyState < 1) return;
    const p = journeyVideo.play();
    if (p && p.then) {
      p.then(() => {
        journeyPrimed = true;
        journeyVideo.pause();
        scheduleScroll();
      }).catch(() => {
        /* Retried on the next interaction. */
      });
    } else {
      journeyPrimed = true;
      journeyVideo.pause();
    }
  }
  for (const type of ["pointerdown", "touchstart", "keydown", "wheel", "scroll"]) {
    window.addEventListener(type, primeJourney, { passive: true });
  }
  // The stage is revealed as soon as a frame can be shown, whichever event says
  // so first: some browsers fire canplay or seeked before loadeddata.
  function markJourneyReady() {
    if (!journeyReady && journeyVideo.readyState >= 2) {
      journeyReady = true;
      worldStage.classList.add("is-journey-ready");
    }
    scheduleScroll();
  }
  journeyVideo.addEventListener("loadedmetadata", () => {
    primeJourney();
    scheduleScroll();
  });
  journeyVideo.addEventListener("loadeddata", markJourneyReady);
  journeyVideo.addEventListener("canplay", markJourneyReady);
  journeyVideo.addEventListener("seeking", () => {
    seekStartedAt = performance.now();
  });
  journeyVideo.addEventListener("seeked", () => {
    seekStartedAt = 0;
    markJourneyReady();
  });
  journeyVideo.addEventListener("error", () => {
    journeyReady = false;
    journeyPrimed = false;
    worldStage.classList.remove("is-journey-ready");   // the poster (first frame) stays
    // A dropped connection mid-load is retried twice before the poster is final.
    if (journeyRetries < 2) {
      journeyRetries += 1;
      setTimeout(() => {
        journeyVideo.src = journeySource();
        journeyVideo.load();
      }, 1500 * journeyRetries);
    }
  });

  function measureRail() {
    beatTops = beats.map((beat) => beat.getBoundingClientRect().top + window.scrollY);
    trackEnd = worldTrack.getBoundingClientRect().bottom + window.scrollY;
    scheduleScroll();
  }

  // Piecewise-linear map from scroll position to seconds through the anchors.
  function journeyTime(y) {
    const viewport = window.innerHeight;
    const anchors = [0, beatTops[1], beatTops[2], beatTops[3], Math.min(beatTops[4], trackEnd - viewport)].map((v, i, arr) =>
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
    revealInView();
    if (!canMoveScene()) return;
    loadJourney();
    if (y > trackEnd) return;                   // the stage has scrolled away
    const duration = Number.isFinite(journeyVideo.duration) && journeyVideo.duration > 1 ? journeyVideo.duration : JOURNEY_LENGTH;
    const target = Math.min(duration - 0.05, journeyTime(y) * (duration / JOURNEY_LENGTH));
    // One seek in flight at a time; a seek that has not completed in 400 ms is
    // treated as dropped and re-issued, so a fast flick can never leave the
    // playhead stranded on an old frame.
    const seekStuck = journeyVideo.seeking && seekStartedAt && performance.now() - seekStartedAt > 400;
    if (journeyVideo.readyState >= 1 && (!journeyVideo.seeking || seekStuck) && Math.abs(journeyVideo.currentTime - target) > 1 / 48) {
      seekStartedAt = performance.now();
      journeyVideo.currentTime = target;
    }
    const progress = clamp((y - beatTops[1]) / Math.max(1, trackEnd - viewport - beatTops[1]));
    worldStage.style.setProperty("--journey-progress", `${(progress * 100).toFixed(1)}%`);
  }
  function scheduleScroll() {
    if (!scrollFrame) scrollFrame = requestAnimationFrame(renderScroll);
  }
  measureRail();
  renderScroll();
  window.addEventListener("scroll", scheduleScroll, { passive: true });
  window.addEventListener("resize", measureRail, { passive: true });
  if ("ResizeObserver" in window) new ResizeObserver(measureRail).observe(worldTrack);
  if (document.fonts?.ready) document.fonts.ready.then(measureRail);
  document.addEventListener("visibilitychange", scheduleScroll);

  // The codex: three tabs (Chikimons, Avatars, Chikimounts) and one dialog that
  // opens a Chikimon as a 3D turntable, or an avatar or mount as its artwork,
  // with its legend from legends.js. The <model-viewer> element is fetched the
  // first time a Chikimon is opened, never on page load.
  const codexTabs = [...document.querySelectorAll(".codex-tab")];
  function selectTab(tab, focus) {
    for (const other of codexTabs) {
      const on = other === tab;
      other.setAttribute("aria-selected", String(on));
      other.tabIndex = on ? 0 : -1;
      document.getElementById(other.getAttribute("aria-controls")).hidden = !on;
    }
    if (focus) tab.focus();
    measureRail(); // the page changed height under the pinned stage
  }
  for (const tab of codexTabs) {
    tab.addEventListener("click", () => selectTab(tab, false));
    tab.addEventListener("keydown", (event) => {
      const index = codexTabs.indexOf(tab);
      let target = null;
      if (event.key === "ArrowRight") target = codexTabs[(index + 1) % codexTabs.length];
      else if (event.key === "ArrowLeft") target = codexTabs[(index + codexTabs.length - 1) % codexTabs.length];
      else if (event.key === "Home") target = codexTabs[0];
      else if (event.key === "End") target = codexTabs[codexTabs.length - 1];
      if (target) {
        event.preventDefault();
        selectTab(target, true);
      }
    });
  }

  const codexDialog = document.getElementById("codex-dialog");
  const codexStill = codexDialog.querySelector(".codex-still");
  const codexSlot = codexDialog.querySelector(".codex-viewer-slot");
  const codexHint = codexDialog.querySelector(".codex-hint");
  const codexKicker = codexDialog.querySelector(".codex-kicker");
  const codexTitle = codexDialog.querySelector("#codex-title");
  const codexSubtitle = codexDialog.querySelector(".codex-subtitle");
  const codexLegend = codexDialog.querySelector(".codex-legend");
  const codexHome = codexDialog.querySelector(".codex-home");
  const ELEMENT_GLOW = {
    fire: "rgba(255, 137, 53, 0.5)",
    water: "rgba(93, 204, 244, 0.46)",
    light: "rgba(255, 204, 83, 0.5)",
    storm: "rgba(190, 120, 255, 0.48)",
    beast: "rgba(120, 220, 150, 0.46)",
  };
  let viewerReady = null;
  let codexOpener = null;
  let codexCurrent = null;
  function loadViewer() {
    if (!viewerReady) {
      viewerReady = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.type = "module";
        script.src = "/site-assets/model-viewer.min.js?v=4.0.0";
        script.onload = () => customElements.whenDefined("model-viewer").then(resolve, reject);
        script.onerror = reject;
        document.head.appendChild(script);
      });
      viewerReady.catch(() => { viewerReady = null; });
    }
    return viewerReady;
  }
  function paragraph(text) {
    const p = document.createElement("p");
    p.textContent = text;
    return p;
  }
  function openCodex(ref, opener) {
    const codex = window.CHIKORIA_CODEX;
    const [kind, key] = ref.split(":");
    const entry = codex && codex[kind] && codex[kind][key];
    if (!entry) return;
    codexOpener = opener;
    codexCurrent = ref;
    codexDialog.style.setProperty("--codex-glow", ELEMENT_GLOW[String(entry.element || "").toLowerCase()] || "rgba(144, 121, 218, 0.4)");
    codexKicker.textContent = kind === "chikimon"
      ? `${entry.element} · ${entry.cls === "legendary" ? "Legendary" : "Chikimon"}`
      : entry.kicker || "";
    codexTitle.textContent = entry.name;
    codexSubtitle.textContent = entry.title || "";
    codexSubtitle.hidden = !entry.title;
    codexLegend.replaceChildren(...entry.legend.map(paragraph));
    codexHome.hidden = !entry.home;
    if (entry.home) {
      const strong = document.createElement("strong");
      strong.textContent = entry.home;
      codexHome.replaceChildren("Found in ", strong);
    }
    codexStill.src = entry.art;
    codexStill.alt = `${entry.name} artwork`;
    codexStill.classList.toggle("is-scene", kind === "mount");
    codexStill.hidden = false;
    codexSlot.replaceChildren();
    codexHint.hidden = true;
    if (!codexDialog.open) codexDialog.showModal();
    codexDialog.querySelector(".codex-copy").scrollTop = 0;
    if (kind !== "chikimon" || !entry.model) return;
    loadViewer().then(() => {
      if (codexCurrent !== ref || !codexDialog.open) return;
      const viewer = document.createElement("model-viewer");
      viewer.setAttribute("src", entry.model);
      viewer.setAttribute("alt", `${entry.name} as a 3D model you can turn`);
      viewer.setAttribute("camera-controls", "");
      viewer.setAttribute("touch-action", "pan-y");
      viewer.setAttribute("interaction-prompt", "none");
      viewer.setAttribute("shadow-intensity", "0.7");
      viewer.setAttribute("exposure", "1.05");
      viewer.setAttribute("camera-orbit", "30deg 78deg auto");
      viewer.setAttribute("loading", "eager");
      viewer.setAttribute("auto-rotate", "");
      viewer.setAttribute("rotation-per-second", "22deg");
      viewer.addEventListener("load", () => {
        codexStill.hidden = true;
        codexHint.hidden = false;
      }, { once: true });
      viewer.addEventListener("error", () => {
        viewer.remove(); // the artwork underneath stays
        codexStill.hidden = false;
      }, { once: true });
      codexSlot.replaceChildren(viewer);
    }).catch(() => {
      /* No viewer: the artwork is already showing. */
    });
  }
  function closeCodex() {
    if (codexDialog.open) codexDialog.close();
  }
  codexDialog.addEventListener("close", () => {
    codexSlot.replaceChildren();
    codexCurrent = null;
    if (codexOpener && codexOpener.isConnected) codexOpener.focus();
  });
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-codex]");
    if (button) openCodex(button.dataset.codex, button);
  });
  codexDialog.querySelector(".codex-close").addEventListener("click", closeCodex);
  codexDialog.addEventListener("click", (event) => {
    if (event.target === codexDialog) closeCodex();
  });
  codexDialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    closeCodex();
  });

  // Gameplay clips are click-to-play and never autoplay. Each <video> ships
  // preload="none", so only its poster loads until a visitor presses play.
  // Native controls stay in the markup for no-JS visitors; with JS the one
  // play button stands in for them until the clip starts. Chikiseum has no
  // clip yet and stays a static preview (see SITE-FOOTAGE.md).
  const gameplayVideos = [];
  for (const media of document.querySelectorAll(".gameplay-media.has-clip")) {
    const video = media.querySelector(".gameplay-video");
    const play = media.querySelector(".gameplay-play");
    gameplayVideos.push(video);
    video.controls = false;
    play.addEventListener("click", () => {
      media.classList.add("is-playing");
      video.controls = true;
      video.play().catch(() => {
        /* Native controls remain available when play() is refused. */
      });
      video.focus({ preventScroll: true });
    });
    video.addEventListener("play", () => {
      for (const other of gameplayVideos) if (other !== video) other.pause();
    });
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      introVideo.pause();
      for (const video of gameplayVideos) video.pause();
    } else scheduleScroll();
  });
})();
