/**
 * A dental clinic you walk through by scrolling.
 *
 * Four stops along one corridor in Z: the street outside, the reception desk,
 * the consult corner where you book, and the operatory. Scroll position drives
 * the camera between waypoints; nothing moves on its own, so the page responds
 * to you rather than performing at you.
 *
 * Every prop is built from primitives at runtime. No model files, no loader,
 * no download — which keeps it small and means it works on the kind of
 * connection a provincial clinic actually has.
 *
 * Layout, front to back:
 *   z = +6   the shopfront, with the door punched through it
 *   z =  0   reception, desk to the RIGHT of the walkway
 *   z = -8   the consult corner, to the LEFT
 *   z = -16  the operatory, chair to the RIGHT
 *
 * Each act's subject sits on the opposite side to its text panel, so the copy
 * never covers the thing it is describing.
 */
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

type Waypoint = { pos: [number, number, number]; look: [number, number, number] };

/**
 * Generated meshes that replace the hand-built stand-ins once they arrive.
 * The scene renders immediately from primitives and swaps each prop in as its
 * file loads, so a slow or failed download degrades to the blocky version
 * rather than to an empty room.
 *
 * `height` is the real-world height in metres the mesh is scaled to — a
 * generated model arrives at an arbitrary scale and has to be fitted to the
 * room rather than trusted.
 */
const PROPS: Record<
  string,
  { file: string; height: number; pos: [number, number, number]; rotY: number; float?: boolean }
> = {
  chair: { file: 'chair.glb', height: 1.4, pos: [1.5, 0, -16.3], rotY: Math.PI * 0.85 },
  cart: { file: 'cart.glb', height: 1.15, pos: [0.15, 0, -15.0], rotY: 0.6 },
  // The generated lamp came with its own floor stand, so it rests on the
  // ground beside the chair rather than hanging.
  light: { file: 'light.glb', height: 2.1, pos: [2.9, 0, -17.2], rotY: -0.5 },
  desk: { file: 'desk.glb', height: 1.12, pos: [1.7, 0, -0.3], rotY: 0.1 },
  bench: { file: 'bench.glb', height: 0.85, pos: [-3.4, 0, 1.6], rotY: Math.PI / 2 },
};

const WAYPOINTS: Waypoint[] = [
  // Back from the kerb, tilted up: the whole shopfront, above the text panel.
  { pos: [0, 2.2, 17.5], look: [0, 4.1, 6] },
  // Inside, close to the desk. Sat further left the right-hand wall filled a
  // third of the frame and the desk read as a distant smudge.
  { pos: [-0.4, 1.55, 3.1], look: [1.7, 1.1, -1.0] },
  // Turned toward the consult corner on the left; panel sits right.
  { pos: [1.7, 1.6, -3.4], look: [-1.9, 1.2, -8.6] },
  // Alongside the chair, looking down the length of it; panel sits left.
  { pos: [-1.7, 1.75, -11.4], look: [1.0, 1.05, -16.6] },
];

const C = {
  brick: 0xe3d9cb,
  brickDark: 0xcfc2ae,
  wall: 0xf1ede6,
  floor: 0xe8e2d8,
  pavement: 0xd6cfc4,
  accent: 0x0b6557,
  accentDeep: 0x083f37,
  accentSoft: 0x8fc9bb,
  warm: 0xd9a441,
  metal: 0xb9c2bd,
  metalDark: 0x8d9894,
  fabric: 0x3f6f64,
  skin: 0xd8b295,
  skin2: 0xc08d68,
  glass: 0xcfe4e4,
};

const box = (w: number, h: number, d: number) => new THREE.BoxGeometry(w, h, d);
const mat = (color: number, o: THREE.MeshLambertMaterialParameters = {}) =>
  new THREE.MeshLambertMaterial({ color, ...o });

function put(
  parent: THREE.Object3D,
  geo: THREE.BufferGeometry,
  m: THREE.Material,
  x: number,
  y: number,
  z: number,
  /** Marks this mesh as a stand-in for the named generated prop. */
  tag?: string
) {
  const mesh = new THREE.Mesh(geo, m);
  mesh.position.set(x, y, z);
  if (tag) mesh.userData.prop = tag;
  parent.add(mesh);
  return mesh;
}

/** Scale a generated mesh to a real height and seat it where the room needs it. */
function fitInto(obj: THREE.Object3D, p: (typeof PROPS)[string]) {
  const size = new THREE.Box3().setFromObject(obj).getSize(new THREE.Vector3());
  obj.scale.setScalar(p.height / Math.max(size.y, 1e-6));
  obj.rotation.y = p.rotY;
  obj.updateMatrixWorld(true);

  const box = new THREE.Box3().setFromObject(obj);
  const c = box.getCenter(new THREE.Vector3());
  obj.position.x += p.pos[0] - c.x;
  obj.position.z += p.pos[2] - c.z;
  // Floor-standing props rest on the ground; a hanging lamp centres instead.
  obj.position.y += p.float ? p.pos[1] - c.y : p.pos[1] - box.min.y;
}

/**
 * Fetch a mesh as raw bytes. A `.txt` sidecar holds the same GLB base64-encoded,
 * for hosts that refuse to serve `.glb` — costs a third more bytes, so it is
 * only ever the fallback.
 */
async function fetchMesh(url: string): Promise<ArrayBuffer> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  if (!url.endsWith('.txt')) return res.arrayBuffer();
  const bin = atob((await res.text()).trim());
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

/** Load each generated prop, hiding its stand-in only once it is actually in. */
function loadProps(scene: THREE.Scene) {
  const loader = new GLTFLoader();
  for (const [key, p] of Object.entries(PROPS)) {
    // Resolved against the page, NOT `import.meta.url`: the bundler rewrites
    // that pattern into a static asset map, and these files live in public/
    // rather than src/, so the map is empty and every lookup came back
    // undefined. Against document.baseURI the bundler leaves it alone.
    const url = new URL(`models/${p.file}`, document.baseURI).href;

    void (async () => {
      let buffer: ArrayBuffer;
      try {
        buffer = await fetchMesh(url);
      } catch {
        try {
          buffer = await fetchMesh(`${url}.txt`);
        } catch {
          return; // Neither form available: the stand-in stays.
        }
      }
      loader.parse(
        buffer,
        '',
        (gltf) => {
          fitInto(gltf.scene, p);
          scene.add(gltf.scene);
          scene.traverse((o) => {
            if (o.userData.prop === key) o.visible = false;
          });
        },
        () => {
          /* Unparseable mesh: keep the stand-in rather than a hole. */
        }
      );
    })();
  }
}

/** A stylised person: no face, friendly proportions, deliberately not lifelike. */
function figure(o: { top: number; bottom: number; skin?: number; seated?: boolean }) {
  const g = new THREE.Group();
  const legH = o.seated ? 0.5 : 0.85;
  put(g, new THREE.CapsuleGeometry(0.17, legH, 4, 8), mat(o.bottom), 0, legH / 2 + 0.17, 0);
  put(g, new THREE.CapsuleGeometry(0.23, 0.46, 4, 10), mat(o.top), 0, legH + 0.52, 0);
  put(g, new THREE.SphereGeometry(0.175, 16, 12), mat(o.skin ?? C.skin), 0, legH + 1.03, 0);
  for (const s of [-1, 1]) {
    const arm = put(g, new THREE.CapsuleGeometry(0.075, 0.42, 4, 8), mat(o.top), s * 0.28, legH + 0.55, 0);
    arm.rotation.z = s * 0.18;
  }
  if (o.seated) put(g, box(0.42, 0.16, 0.46), mat(o.bottom), 0, legH + 0.14, 0.22);
  return g;
}

function buildScene(scene: THREE.Scene) {
  const g = new THREE.Group();

  // --- ground -------------------------------------------------------------
  const pavement = put(g, new THREE.PlaneGeometry(70, 40), mat(C.pavement), 0, 0.01, 22);
  pavement.rotation.x = -Math.PI / 2;
  const floor = put(g, new THREE.PlaneGeometry(10, 28), mat(C.floor), 0, 0.02, -8);
  floor.rotation.x = -Math.PI / 2;

  // --- shopfront at z = 6 -------------------------------------------------
  // The door is a gap between two piers under a lintel, rather than CSG.
  const fa = new THREE.Group();
  for (const s of [-1, 1]) put(fa, box(3.75, 5.6, 0.45), mat(C.brick), s * 3.63, 2.8, 6);
  put(fa, box(3.5, 1.6, 0.45), mat(C.brick), 0, 4.8, 6);
  put(fa, box(11.4, 0.45, 0.7), mat(C.brickDark), 0, 5.82, 6.05); // parapet
  put(fa, box(6.6, 0.3, 1.8), mat(C.accent), 0, 4.0, 6.95); // canopy
  const sign = put(fa, box(4.2, 1.0, 0.2), mat(C.accent), 0, 5.0, 6.6);
  put(fa, new THREE.SphereGeometry(0.19, 14, 10), mat(0xffffff), -1.55, 5.0, 6.74);
  for (const x of [-3.63, 3.63]) {
    put(fa, box(2.6, 2.0, 0.12), mat(C.glass, { transparent: true, opacity: 0.9 }), x, 2.9, 6.26);
    put(fa, box(2.9, 0.16, 0.2), mat(C.brickDark), x, 1.78, 6.3); // sill
  }
  // Glass doors in the opening, slightly ajar.
  for (const s of [-1, 1]) {
    const d = put(fa, box(1.6, 3.3, 0.08), mat(C.glass, { transparent: true, opacity: 0.55 }), s * 0.9, 1.65, 6.1);
    d.rotation.y = s * 0.22;
  }
  put(fa, box(5.2, 0.16, 1.4), mat(C.brickDark), 0, 0.08, 7.3); // step
  for (const x of [-2.9, 2.9]) {
    put(fa, new THREE.CylinderGeometry(0.34, 0.28, 0.56, 12), mat(0xc9a882), x, 0.28, 8.0);
    put(fa, new THREE.SphereGeometry(0.46, 12, 10), mat(0x6f9e7d), x, 0.85, 8.0);
  }
  g.add(fa);

  // --- interior shell -----------------------------------------------------
  for (const s of [-1, 1]) put(g, box(0.3, 4.3, 26), mat(C.wall), s * 5, 2.15, -7);
  const ceil = put(g, new THREE.PlaneGeometry(10, 26), mat(0xfbf8f3), 0, 4.3, -7);
  ceil.rotation.x = Math.PI / 2;
  put(g, box(10, 4.3, 0.3), mat(C.wall), 0, 2.15, -20);

  // --- act 2: reception, desk on the right --------------------------------
  const rec = new THREE.Group();
  put(rec, box(3.8, 1.05, 0.85), mat(C.accent), 2.0, 0.53, 0, 'desk');
  put(rec, box(4.1, 0.13, 1.1), mat(0xf6f2ea), 2.0, 1.12, 0, 'desk');
  const mon = put(rec, box(0.9, 0.55, 0.06), mat(0x22302c), 1.5, 1.5, -0.15);
  mon.rotation.y = 0.5;
  const monFace = put(rec, box(0.8, 0.46, 0.02), mat(C.accentSoft), 1.54, 1.5, -0.11);
  monFace.rotation.y = 0.5;

  const receptionist = figure({ top: C.accentSoft, bottom: 0x2f4d47 });
  receptionist.position.set(2.3, 0, -1.0);
  receptionist.rotation.y = Math.PI - 0.25;
  rec.add(receptionist);

  // Waiting side, opposite the desk.
  for (let i = 0; i < 3; i++) {
    const z = 2.6 - i * 0.82;
    put(rec, box(0.64, 0.12, 0.62), mat(C.fabric), -3.5, 0.46, z, 'bench');
    put(rec, box(0.14, 0.64, 0.62), mat(C.fabric), -3.84, 0.78, z, 'bench');
  }
  const waiting = figure({ top: C.warm, bottom: 0x4a4a52, seated: true });
  waiting.position.set(-3.4, 0.3, 1.78);
  waiting.rotation.y = Math.PI / 2;
  rec.add(waiting);
  g.add(rec);

  // --- act 3: consult corner on the left ----------------------------------
  const con = new THREE.Group();
  put(con, new THREE.CylinderGeometry(0.78, 0.73, 0.1, 20), mat(0xf0ebe2), -2.0, 0.78, -8.4);
  put(con, new THREE.CylinderGeometry(0.1, 0.17, 0.78, 12), mat(C.metal), -2.0, 0.39, -8.4);
  const tablet = put(con, box(0.56, 0.03, 0.4), mat(0x1d2a27), -2.0, 0.85, -8.4);
  tablet.rotation.y = 0.5;
  const tabFace = put(con, box(0.5, 0.01, 0.35), mat(C.accentSoft), -2.0, 0.87, -8.4);
  tabFace.rotation.y = 0.5;

  const dentist = figure({ top: 0xf4f6f4, bottom: C.accent, skin: C.skin2 });
  dentist.position.set(-3.1, 0, -9.1);
  dentist.rotation.y = 0.9;
  con.add(dentist);

  const patient = figure({ top: 0xe4b7a0, bottom: 0x53565e, seated: true });
  patient.position.set(-1.3, 0.3, -7.6);
  patient.rotation.y = -1.9;
  con.add(patient);
  for (const [x, z, r] of [[-3.1, -9.1, 0.9], [-1.3, -7.6, -1.9]] as const) {
    const stool = put(con, new THREE.CylinderGeometry(0.27, 0.25, 0.12, 14), mat(C.fabric), x, 0.5, z);
    stool.visible = r < 0; // only the seated one needs a seat under them
  }
  g.add(con);

  // --- act 4: the operatory, chair on the right ---------------------------
  const op = new THREE.Group();
  put(op, new THREE.CylinderGeometry(0.44, 0.58, 0.18, 16), mat(C.metalDark), 1.0, 0.09, -16, 'chair');
  put(op, new THREE.CylinderGeometry(0.17, 0.21, 0.68, 12), mat(C.metal), 1.0, 0.5, -16, 'chair');
  put(op, box(0.78, 0.22, 1.5), mat(C.accent), 1.0, 0.94, -16.1, 'chair');
  const back = put(op, box(0.78, 0.22, 1.3), mat(C.accent), 1.0, 1.2, -17.1, 'chair');
  back.rotation.x = -0.36;
  const head = put(op, box(0.54, 0.2, 0.42), mat(C.accentDeep), 1.0, 1.58, -17.76, 'chair');
  head.rotation.x = -0.36;

  // Overhead light, dropped from the ceiling behind the chair rather than on
  // a long articulated arm — at eye level the arm just crossed the frame as
  // two sticks, and the dome read as a grey blob seen edge-on.
  put(op, new THREE.CylinderGeometry(0.06, 0.06, 1.35, 8), mat(C.metal), 2.5, 3.6, -16.4, 'light');
  const elbow = put(op, new THREE.CylinderGeometry(0.06, 0.06, 1.55, 8), mat(C.metal), 1.78, 2.95, -16.35, 'light');
  elbow.rotation.z = Math.PI / 2;
  // A flattened disc reads as a lamp from the side; a hemisphere does not.
  put(op, new THREE.CylinderGeometry(0.5, 0.44, 0.17, 24), mat(0xf4f6f4), 1.05, 2.42, -16.2, 'light');
  put(op, new THREE.CylinderGeometry(0.43, 0.43, 0.05, 24), new THREE.MeshBasicMaterial({ color: 0xfff4d6 }), 1.05, 2.31, -16.2, 'light');
  const glow = new THREE.PointLight(0xfff0cc, 5, 5.5, 2.4);
  glow.position.set(1.05, 2.15, -16.2);
  op.add(glow);

  // Instrument tray, tools in a cup.
  put(op, new THREE.CylinderGeometry(0.045, 0.045, 0.98, 8), mat(C.metal), 2.3, 0.49, -15.5);
  put(op, box(0.66, 0.05, 0.46), mat(0xdfe5e1), 2.3, 0.99, -15.5);
  put(op, new THREE.CylinderGeometry(0.095, 0.085, 0.19, 12), mat(0xcdd6d1), 2.42, 1.1, -15.42);
  for (let i = 0; i < 4; i++) {
    const t = put(op, new THREE.CylinderGeometry(0.013, 0.013, 0.36, 6), mat(i % 2 ? 0xa9b3ad : 0xdcd2b8), 2.38 + i * 0.03, 1.29, -15.42 + (i - 1.5) * 0.03);
    t.rotation.z = (i - 1.5) * 0.07;
  }

  // Delivery unit and operator stool.
  put(op, box(0.6, 1.05, 0.5), mat(0xeef1ee), -0.4, 0.52, -15.4, 'cart');
  put(op, box(0.56, 0.06, 0.46), mat(C.metal), -0.4, 1.08, -15.4, 'cart');
  put(op, new THREE.CylinderGeometry(0.28, 0.26, 0.12, 14), mat(C.fabric), 0.0, 0.62, -16.8);
  put(op, new THREE.CylinderGeometry(0.05, 0.05, 0.56, 8), mat(C.metal), 0.0, 0.3, -16.8);

  // A cabinet run along the back so the room has a wall, not a void.
  put(op, box(6.5, 0.9, 0.55), mat(0xf4f1ea), 0, 0.45, -19.4);
  put(op, box(6.7, 0.07, 0.62), mat(C.metalDark), 0, 0.93, -19.4);
  g.add(op);

  scene.add(g);
}

export function mountClinicScene(root: HTMLElement) {
  const canvas = root.querySelector<HTMLCanvasElement>('[data-scene-canvas]');
  if (!canvas) return;

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  } catch {
    // No WebGL: the page is written to read without it.
    root.setAttribute('data-scene-failed', '');
    return;
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(46, 1, 0.1, 140);

  // Bounced up a little: the first pass left interiors reading brown.
  scene.add(new THREE.HemisphereLight(0xffffff, 0xeae4da, 0.85));
  const key = new THREE.DirectionalLight(0xfff4e2, 0.85);
  key.position.set(6, 11, 9);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xdfeef0, 0.4);
  fill.position.set(-7, 5, -8);
  scene.add(fill);

  // The generated props carry PBR materials, which need something to reflect
  // or they render as flat grey — metal especially goes black. A generated
  // room environment gives them that without shipping an HDR file.
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  // Enough to light the props' metal, not so much that it bleaches the walls.
  scene.environmentIntensity = 0.3;

  buildScene(scene);
  loadProps(scene);

  // Background follows the page so the scene sits inside the design.
  const syncTheme = () => {
    const bg = new THREE.Color(getComputedStyle(document.body).backgroundColor);
    scene.background = bg;
    scene.fog = new THREE.Fog(bg.getHex(), 26, 62);
  };
  syncTheme();
  new MutationObserver(syncTheme).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme'],
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', syncTheme);

  function resize() {
    // Size from the CANVAS, not from `root`: root is the whole scrolling
    // wrapper and is several viewports tall, which would give the camera a
    // portrait aspect and squeeze everything into the middle of the frame.
    const w = canvas.clientWidth || 1;
    const h = canvas.clientHeight || 1;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  resize();
  new ResizeObserver(resize).observe(canvas);

  const eye = new THREE.Vector3();
  const target = new THREE.Vector3();
  const eyeGoal = new THREE.Vector3();
  const targetGoal = new THREE.Vector3();
  const pointer = { x: 0, y: 0 };

  /** 0 at the top of the scene, 1 once the last act is reached. */
  function progress() {
    const span = root.offsetHeight - innerHeight;
    if (span <= 0) return 0;
    return Math.min(1, Math.max(0, -root.getBoundingClientRect().top / span));
  }

  function sample(t: number) {
    const last = WAYPOINTS.length - 1;
    const scaled = t * last;
    const i = Math.min(last - 1, Math.floor(scaled));
    const f = scaled - i;
    const e = f * f * (3 - 2 * f); // smoothstep: arrive, don't snap
    const a = WAYPOINTS[i];
    const b = WAYPOINTS[i + 1];
    eyeGoal.set(
      a.pos[0] + (b.pos[0] - a.pos[0]) * e,
      a.pos[1] + (b.pos[1] - a.pos[1]) * e,
      a.pos[2] + (b.pos[2] - a.pos[2]) * e
    );
    targetGoal.set(
      a.look[0] + (b.look[0] - a.look[0]) * e,
      a.look[1] + (b.look[1] - a.look[1]) * e,
      a.look[2] + (b.look[2] - a.look[2]) * e
    );
  }

  sample(progress());
  eye.copy(eyeGoal);
  target.copy(targetGoal);

  if (!reduced) {
    addEventListener('pointermove', (e) => {
      pointer.x = (e.clientX / innerWidth - 0.5) * 0.45;
      pointer.y = (e.clientY / innerHeight - 0.5) * 0.26;
    });
  }

  let running = true;
  function frame() {
    if (!running) return;
    sample(progress());
    if (reduced) {
      eye.copy(eyeGoal);
      target.copy(targetGoal);
    } else {
      eye.lerp(eyeGoal, 0.085);
      target.lerp(targetGoal, 0.085);
    }
    camera.position.set(eye.x + pointer.x, eye.y - pointer.y, eye.z);
    camera.lookAt(target);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  frame();

  // Stop drawing off screen or in a hidden tab. A canvas rendering behind a
  // scrolled-past section is pure battery drain.
  new IntersectionObserver(
    ([entry]) => {
      running = entry.isIntersecting && !document.hidden;
      if (running) frame();
    },
    { rootMargin: '10% 0px' }
  ).observe(root);
  document.addEventListener('visibilitychange', () => {
    running = !document.hidden && root.getBoundingClientRect().bottom > 0;
    if (running) frame();
  });
}
