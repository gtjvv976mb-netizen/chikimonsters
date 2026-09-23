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

  // Enhancement only: all sections remain readable without JS.
  if ("IntersectionObserver" in window) {
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

  // Gameplay footage is intentionally not wired yet. The four static preview
  // cards in index.html carry data-video-slot IDs (exploration, gathering,
  // wicked-temple, chikiseum). When verified footage is available, add a
  // poster and a click-to-play video for each matching slot; never autoplay.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) introVideo.pause();
    else scheduleScroll();
  });
})();
