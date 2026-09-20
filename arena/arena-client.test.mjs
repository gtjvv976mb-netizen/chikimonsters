import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const html = readFileSync(new URL("./index.html", import.meta.url), "utf8");
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(match => match[1]);
const begin = scripts.at(-1).indexOf("const esc =");
const end = scripts.at(-1).indexOf("// ---------------------------------------------------------------- state", begin);
assert(begin >= 0 && end > begin);

function element(tag){
  return {
    tag, children: [], textContent: "", className: "",
    append(...children){ this.children.push(...children); },
    replaceChildren(){ this.children = []; },
    setAttribute(name, value){ this[name] = value; }
  };
}
const { esc, traitSummary, traitDetail, setTrait } = vm.runInNewContext(
  `(()=>{${scripts.at(-1).slice(begin, end)}return {esc, traitSummary, traitDetail, setTrait};})()`,
  { document: { createElement: element } }
);

test("all inline arena scripts parse without changing wager code", () => {
  for (const script of scripts) new Function(script);
});

test("NFT names and server fields cannot become HTML in roster, logs, cards or wagers", () => {
  const payload = `<img src=x onerror="alert(1)">&'`;
  assert.equal(esc(payload), "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;&amp;&#39;");
  for (const field of [
    "f.display_name", "f.rarity", "f.reason", "t.handle", "t.fighter.display_name",
    "card.name", "ev.status", "ev.reason", "w.challenger.handle",
    "w.challenger.fighter.display_name", "l.reason"
  ]) {
    assert.ok(!html.includes("${" + field + "}"), `unescaped HTML interpolation: ${field}`);
  }
});

test("trait inspection uses text nodes and explains each server-owned attribute", () => {
  const host = element("div");
  const fighter = { trait: {
    name: "<svg onload=alert(1)>", signature_arch: "strike", signature_effect: "fury",
    stride: 1.05, focus: 1.03, ward: .95, reach: 1
  }};
  setTrait(host, fighter);
  const [summary, detail] = host.children[0].children;
  assert.equal(summary.textContent, "✦ " + traitSummary(fighter));
  assert.match(summary.textContent, /<svg/);
  assert.match(detail.textContent, /Stride 105% · Focus 103% · Ward 95% · Reach 100%/);
  assert.match(traitDetail(fighter), /confirmed hit/);
  assert.equal(summary.innerHTML, undefined);
  assert.equal(detail.innerHTML, undefined);
  setTrait(host, {});
  assert.equal(host.children.length, 0);
});

test("a same-size hand refreshes when the next duel fields another species", () => {
  const source = scripts.at(-1);
  const beginHand = source.indexOf("function drawHand(s){");
  const endHand = source.indexOf("async function castSlot", beginHand);
  assert(beginHand >= 0 && endHand > beginHand);
  const handEl = {
    children: [],
    get childElementCount(){ return this.children.length; },
    set innerHTML(value){ if (value === "") this.children = []; },
    appendChild(child){ this.children.push(child); }
  };
  const drawHand = vm.runInNewContext(
    `(()=>{const $=()=>handEl;function castSlot(){};${source.slice(beginHand,endHand)}return drawHand;})()`,
    { handEl, document: { createElement: () => ({
      dataset: {}, classList: { toggle(){} },
      querySelector: () => ({ hidden: true, textContent: "" })
    }) }, esc, traitSummary, traitDetail }
  );
  const card = (key, name) => ({ key, name, slot: 0, arch: "strike", cost: 1, range_m: 2 });
  const state = { status: "active", server_time: 0,
    you: { side: "A", hand: [card("firix:0", "Ember Bite")], cooldown_remaining: {} },
    players: [{ side: "A", energy: 3, trait: { signature_arch: "strike", name: "Cinder Rush",
      signature_effect: "fury" } }] };
  drawHand(state);
  const first = handEl.children[0];
  assert.match(first.innerHTML, /Ember Bite/);
  state.you.hand = [card("forestle:0", "Vine Swipe")];
  drawHand(state);
  assert.notEqual(handEl.children[0], first);
  assert.match(handEl.children[0].innerHTML, /Vine Swipe/);
  drawHand(state);
  assert.equal(handEl.children.length, 1);
});
