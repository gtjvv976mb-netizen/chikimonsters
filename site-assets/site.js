(() => {
  "use strict";

  const header = document.querySelector(".site-header");
  const menu = document.querySelector(".menu-toggle");
  const links = document.getElementById("nav-links");
  const dialog = document.getElementById("intro-dialog");
  const video = document.getElementById("intro-video");
  const watch = document.getElementById("watch-intro");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const desktopMotion = window.matchMedia(
    "(min-width: 761px) and (prefers-reduced-motion: no-preference)",
  );

  document.getElementById("year").textContent = String(
    new Date().getFullYear(),
  );

  const updateHeader = () =>
    header.classList.toggle("is-scrolled", window.scrollY > 30);
  updateHeader();
  window.addEventListener("scroll", updateHeader, { passive: true });

  function setMenu(open) {
    menu.setAttribute("aria-expanded", String(open));
    menu.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    links.classList.toggle("is-open", open);
    header.classList.toggle("menu-open", open);
  }
  menu.addEventListener("click", () =>
    setMenu(menu.getAttribute("aria-expanded") !== "true"),
  );
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
        /* private mode */
      }
    });
  }

  function closeIntro() {
    video.pause();
    video.removeAttribute("src");
    video.load();
    if (dialog.open) dialog.close();
  }
  watch.addEventListener("click", () => {
    dialog.showModal();
    video.src = "/intro.mp4";
    const play = video.play();
    if (play && play.catch)
      play.catch(() => {
        /* controls remain available */
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

  // Reveals are enhancement-only: a failed script or older browser never hides content.
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
      { threshold: 0.1, rootMargin: "0px 0px -35px 0px" },
    );
    document
      .querySelectorAll(".reveal")
      .forEach((element) => reveals.observe(element));
  }

  // Real creature motion is loaded only for visible desktop scenes. Mobile and reduced-motion
  // visitors keep the clean static posters, avoiding persistent animation and bandwidth.
  const creatureImages = [
    ...document.querySelectorAll(".hero-creature img[data-loop]"),
  ];
  const saveData = Boolean(
    navigator.connection && navigator.connection.saveData,
  );
  function setCreatureSource(image, active) {
    const target = active ? image.dataset.loop : image.dataset.poster;
    if (image.getAttribute("src") !== target) image.setAttribute("src", target);
  }
  const loopObserver =
    "IntersectionObserver" in window
      ? new IntersectionObserver(
          (entries) => {
            for (const entry of entries) {
              const image = entry.target;
              const shouldLoop =
                entry.isIntersecting &&
                desktopMotion.matches &&
                !saveData &&
                !document.hidden;
              setCreatureSource(image, shouldLoop);
            }
          },
          { threshold: 0.15 },
        )
      : null;
  creatureImages.forEach((image) => {
    image.dataset.poster = image.getAttribute("src");
    if (loopObserver) loopObserver.observe(image);
  });
  function refreshMotion() {
    creatureImages.forEach((image) => {
      const bounds = image.getBoundingClientRect();
      const inView = bounds.bottom > 0 && bounds.top < window.innerHeight;
      setCreatureSource(
        image,
        inView && desktopMotion.matches && !document.hidden && !saveData,
      );
    });
  }
  desktopMotion.addEventListener("change", refreshMotion);
  document.addEventListener("visibilitychange", refreshMotion);

  // A very small pointer response adds depth without scroll-linked work or canvas rendering.
  const hero = document.querySelector(".hero");
  let pointerFrame = 0;
  hero.addEventListener(
    "pointermove",
    (event) => {
      if (
        !desktopMotion.matches ||
        !window.matchMedia("(hover: hover)").matches
      )
        return;
      if (pointerFrame) return;
      const x = (event.clientX / window.innerWidth - 0.5) * 2;
      pointerFrame = requestAnimationFrame(() => {
        hero.querySelectorAll("[data-parallax]").forEach((element) => {
          element.style.setProperty(
            "--shift-x",
            `${x * Number(element.dataset.parallax)}px`,
          );
        });
        pointerFrame = 0;
      });
    },
    { passive: true },
  );
})();
