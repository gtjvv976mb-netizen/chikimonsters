/* Chikiseum wager deposit bridge — the web export's link to the player's wallet.
 *
 * Godot cannot build or sign a Solana transaction, so the deposit is built here and signed by
 * Phantom. Everything else about a wager goes through the arena's own authenticated routes;
 * this file exists only to turn "pay your stake" into one signed transfer.
 *
 * Install:
 *   1. copy this file to realm/chikiseum-wager-bridge.js
 *   2. in realm/index.html, before the engine boots, add:
 *        <script src="https://unpkg.com/@solana/web3.js@1.95.3/lib/index.iife.min.js"
 *                integrity="sha384-xo1g+ODR6i1cxIVZeALc/apXFHeaJHO1j1whMO3dhtdBChWeaihnDs7UnXs9ch78"
 *                crossorigin="anonymous"></script>
 *        <script src="chikiseum-wager-bridge.js"></script>
 *
 *   The integrity hash is not optional. This code builds a transfer of the player's SOL; a CDN
 *   serving altered bytes could change where it goes. With SRI the browser refuses anything
 *   that is not that exact file, and this bridge then reports itself unavailable rather than
 *   running something unverified.
 *
 *   NOTE: promoting a new Godot export overwrites realm/index.html, so either re-apply those
 *   two lines after every export or put them in the export's HTML shell template.
 *
 * From GDScript (web export only):
 *   JavaScriptBridge.eval("ChikiseumWagerBridge.pay(%s)" % JSON.stringify({
 *       treasury = treasury, lamports = lamports, memo = memo }), true)
 *   then poll ChikiseumWagerBridge.result(id) until it is no longer "pending".
 *
 * Deliberately NOT a promise-returning API: Godot's JavaScriptBridge cannot await one. Each
 * call returns an id immediately and the result is collected by polling.
 */
(function () {
  "use strict";

  var MEMO_PROGRAM = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";
  var RPC = "https://api.mainnet-beta.solana.com";
  var jobs = Object.create(null);
  var seq = 0;

  function wallet() {
    return (window.phantom && window.phantom.solana) || null;
  }

  function unavailable(why) {
    return { ok: false, status: "error", error: why };
  }

  /** Is a deposit possible at all right now? Check this before offering the button. */
  function ready() {
    if (!window.solanaWeb3) return unavailable("The Solana library did not load. Reload the page.");
    if (!wallet()) return unavailable("No wallet found. Install Phantom, or open the game in Phantom's browser.");
    return { ok: true, status: "ready" };
  }

  /**
   * Start a deposit. Returns { id } immediately; poll result(id).
   * args: { treasury, lamports, memo }  — all three come from the server, never from the client.
   */
  function pay(args) {
    var id = "w" + (++seq);
    jobs[id] = { status: "pending" };
    var gate = ready();
    if (!gate.ok) { jobs[id] = gate; return { id: id }; }

    var a = typeof args === "string" ? JSON.parse(args) : args;
    // Refuse anything that is not exactly what the server asked for. A deposit with a wrong
    // amount or a missing memo is money the server cannot credit — better to never send it.
    if (!a || typeof a.treasury !== "string" || typeof a.memo !== "string"
        || !Number.isSafeInteger(a.lamports) || a.lamports <= 0) {
      jobs[id] = unavailable("The deposit request was incomplete.");
      return { id: id };
    }

    (function () {
      var web3 = window.solanaWeb3, ph = wallet();
      Promise.resolve()
        .then(function () { return ph.connect(); })
        .then(function (res) {
          var from = new web3.PublicKey(res.publicKey.toString());
          var conn = new web3.Connection(RPC, "confirmed");
          return conn.getLatestBlockhash("confirmed").then(function (bh) {
            var tx = new web3.Transaction();
            tx.add(web3.SystemProgram.transfer({
              fromPubkey: from,
              toPubkey: new web3.PublicKey(a.treasury),
              lamports: a.lamports
            }));
            // The memo is what binds this payment to one wager and one side. Without it the
            // server has a transfer it cannot attribute, so it is never optional.
            tx.add(new web3.TransactionInstruction({
              keys: [],
              programId: new web3.PublicKey(MEMO_PROGRAM),
              data: new TextEncoder().encode(a.memo)
            }));
            tx.feePayer = from;
            tx.recentBlockhash = bh.blockhash;
            return ph.signAndSendTransaction(tx);
          });
        })
        .then(function (sent) {
          jobs[id] = { ok: true, status: "sent", signature: sent.signature };
        })
        .catch(function (e) {
          var msg = (e && e.message) ? e.message : String(e);
          // A user closing the wallet popup is a decision, not a fault. Say so plainly so the
          // game can go back to the panel instead of showing an error.
          var cancelled = /User rejected|reject(ed)? the request|declined/i.test(msg);
          jobs[id] = { ok: false, status: cancelled ? "cancelled" : "error",
                       error: cancelled ? "You cancelled the payment." : msg };
        });
    })();

    return { id: id };
  }

  /** Poll a job. Returns { status: "pending" | "sent" | "cancelled" | "error", … }. */
  function result(id) {
    var job = jobs[id];
    if (!job) return unavailable("Unknown deposit.");
    if (job.status !== "pending") delete jobs[id];   // collected once; do not leak jobs
    return job;
  }

  window.ChikiseumWagerBridge = { ready: ready, pay: pay, result: result, MEMO_PROGRAM: MEMO_PROGRAM };
})();
