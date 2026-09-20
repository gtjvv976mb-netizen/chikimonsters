import Foundation
import WebKit
import UIKit
import Network

/// What the player should be looking at.
enum ShellPhase: Equatable {
    case booting            // the realm is loading; the web layer draws its own progress
    case pairing(String?)   // not linked — the native pairing screen, with an optional reason
    case playing
    case failed(String)     // no page to fall back on: network, load error, content process gone
    case paused(String)     // the server asked us to stand down
    case staleShell         // this binary is older than the web layer supports
    case lockdown           // Lockdown Mode disables WebAssembly; the realm cannot run at all
}

/// Owns the one WKWebView for the process lifetime and speaks the `chikiLink` contract.
///
/// ONE WEB VIEW, FOREVER. The loader keeps its boot guards in `sessionStorage` —
/// `realm-sw-retry`, `realm-was-running`, `realm-loading`, `realm-oom` — which is scoped to the web
/// view's session. Recreating the view, or calling `load()` a second time, resets all of them at
/// once: the cross-origin-isolation retry loses its loop guard, and the out-of-memory detector that
/// drops a memory-killed phone to the lighter pack goes blind. Recovery is always `reload()`.
@MainActor
final class ShellModel: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var phase: ShellPhase = .booting
    @Published private(set) var record: LinkRecord
    @Published private(set) var policyIsLive = false     // proved by a 'ready' message, never assumed

    /// 0…100 while the realm builds itself, plus the loader's own status line. Without this the
    /// app is a black box for the several minutes a cold boot takes.
    @Published private(set) var progress: Int = 0
    @Published private(set) var progressNote: String = ""

    /// Whether the phone is on a connection the player pays for by the megabyte.
    ///
    /// ONLY THE NATIVE SIDE CAN ANSWER THIS. WebKit implements no Network Information API, so
    /// `navigator.connection` is undefined in the web layer on iOS — in Safari and in a WKWebView
    /// alike. The page therefore cannot choose the lighter pack on its own; it waits to be told.
    @Published private(set) var isMetered = false

    private let pathMonitor = NWPathMonitor()

    /// Whether this device may take the 313 MB HD pack instead of the 174 MB lite one.
    ///
    /// THIS DEFAULTS TO NO, AND THAT IS DELIBERATE. The app used to take HD unconditionally. Forced
    /// on a real iPhone — via Safari's Request Desktop Website, which serves the same 313 MB pack
    /// under a slightly harsher budget than the app's — the device ran out of memory. The app is
    /// kinder by a capped device pixel ratio and four fewer workers, but the pack is the same and
    /// the pack is what dominates, so the honest expectation is that it dies too.
    ///
    /// The loader's own memory net would catch it — one kill drops the device to lite for 24 hours
    /// — but that makes a player's FIRST launch a crash and a reload, which is also what an App
    /// Review tester would see.
    ///
    /// THE THRESHOLD BELOW IS A STARTING POINT, NOT A MEASUREMENT. Peak boot holds the reassembled
    /// pack blob, the engine's own copy of it and the compiled wasm at once, so the ceiling is well
    /// above the 353 MB of downloads. 6 GB is the first tier where that is plausibly comfortable.
    /// Raise or lower it from real device testing rather than reasoning — and note that
    /// `physicalMemory` is total RAM, not what iOS will actually let one web content process have.
    static let hdMinimumPhysicalMemory: UInt64 = 6 * 1024 * 1024 * 1024

    static var deviceCanHoldHDPack: Bool {
        // An iPad reports a desktop-class user agent, so the loader already gives it the HD pack
        // and this flag is not consulted for it.
        ProcessInfo.processInfo.physicalMemory >= hdMinimumPhysicalMemory
    }

    var isLinked: Bool { record.isLinked }
    var activeWallet: String { record.activeAccount?.wallet ?? "" }

    // MARK: - Constants

    /// The only page this app ever shows. The path matters: the Cloudflare rule that supplies
    /// cross-origin isolation is scoped to /realm/*, and /arena/ and /link/ are surfaces this app
    /// must never display (a SOL wager client and a Phantom sign-in respectively).
    static let realmURL = URL(string: "https://chikimonsters.com/realm/")!
    static let realmHost = "chikimonsters.com"
    static let realmPathPrefix = "/realm/"

    /// Links the loading screen legitimately offers. Re-validated HERE and not trusted from the
    /// page: `webkit.messageHandlers.chikiLink` lives in the page world, so any script in the realm
    /// — the compiled game pack included — can post an `external-link` of its choosing.
    private static let externalHosts: Set<String> = [
        "x.com", "www.x.com", "twitter.com", "www.twitter.com",
        "discord.gg", "discord.com", "www.discord.com",
    ]

    // MARK: - Web view

    let webView: WKWebView
    private let controller = WKUserContentController()
    private var didStartLoad = false

    override init() {
        record = LinkKeychain.loadOrCreate()

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        // MUST be the default (persistent) store. A non-persistent store starts empty every cold
        // launch, which would discard the reassembled engine chunks in Cache Storage, the player's
        // saves in the IndexedDB filesystem, and the 24-hour memory-kill verdict the loader keeps
        // so a phone that already died does not retry the heavy pack.
        config.websiteDataStore = .default()

        // The boot cinematic is started from JavaScript. Without these two the clip either never
        // plays or is seized by the fullscreen player in the middle of the engine boot.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Pure surface area in a game with no media controls.
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false

        // Leave the content mode at .recommended. The loader routes off the user agent — forcing
        // the desktop mode would turn the phone flag off and hand an iPhone the full-resolution
        // backing store and the desktop worker budget.
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        // Nothing to go back to, and an edge swipe would fight the game's own touch handling.
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        #if DEBUG
        // Without this Safari Web Inspector cannot attach, and every diagnostic the web layer
        // offers — CHIK_POLICY_BLOCKED, CHIK_LINK.status(), CHIK_FEATURES — is unreachable.
        webView.isInspectable = true
        #endif

        // The handler goes in the PAGE world, with no contentWorld argument. chiki-ios.js looks it
        // up as `window.webkit.messageHandlers.chikiLink` and SILENTLY RETURNS if it is absent, so
        // registering it in .defaultClient would mean the Keychain is never written and the app
        // re-pairs on every launch with no error anywhere.
        controller.add(MessageProxy(self), name: "chikiLink")

        startPathMonitor()
        installInjection()
    }

    /// Watch the interface so the pack choice can be made before the download starts, and so a
    /// player who walks off Wi-Fi mid-session is told rather than silently billed.
    ///
    /// `isExpensive` covers cellular and personal hotspots; `isConstrained` is Low Data Mode, which
    /// is the player explicitly asking apps to use less. Either is a reason to take the lite pack.
    private func startPathMonitor() {
        // Read the current path synchronously if one is already available, so the very first
        // injection carries the right answer rather than defaulting to "unmetered" and being
        // corrected after the download has begun.
        isMetered = pathMonitor.currentPath.isExpensive || pathMonitor.currentPath.isConstrained

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let metered = path.isExpensive || path.isConstrained
            Task { @MainActor [weak self] in
                guard let self, metered != self.isMetered else { return }
                self.isMetered = metered
                // Tell the page. It cannot change the pack that is already downloading, but a
                // later launch — and the OOM fallback — will honour it.
                self.webView.evaluateJavaScript("window.CHIK_METERED = \(metered); true;", completionHandler: nil)
                self.installInjection()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.chikimonsters.path"))
    }

    deinit { pathMonitor.cancel() }

    // MARK: - Injection

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Rebuild `window.CHIK_IOS_APP` from the current record and install it as the document-start
    /// script.
    ///
    /// THIS MUST RUN AGAIN ON EVERY `persist`. A WKUserScript is a frozen string captured at
    /// `addUserScript` time and re-run verbatim on every load. The page reloads more than you
    /// think — switching account calls `location.reload()`, and the cross-origin-isolation retry
    /// reloads too — so a stale script would re-inject the pre-change state and silently undo it:
    /// an account switch would revert, and the reload after a first pairing would land unlinked on
    /// a device that had just paired.
    private func installInjection() {
        var payload = record.injectionPayload(
            deviceName: UIDevice.current.model,     // "iPhone" — not the player's device name
            version: appVersion,
            build: appBuild
        )
        // The page cannot see the interface; this is the only way it learns.
        payload["metered"] = isMetered
        // Nor can it see how much memory this phone has — WebKit implements no
        // navigator.deviceMemory. See `deviceCanHoldHDPack`.
        payload["hd"] = Self.deviceCanHoldHDPack
        // The realm ships in English, Japanese and Chinese. The in-game switcher lives inside the
        // compiled pack, so the policy layer — which runs before the game — has no way to read it
        // and uses this instead. The device language is what the player has already told iOS.
        payload["locale"] = Locale.preferredLanguages.first ?? "en"
        // Built with JSONSerialization, never string interpolation: a wallet or label is data, and
        // a stray quote in it would be a script-injection bug in our own shell.
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        let source = "window.CHIK_IOS_APP = \(json);"
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)

        controller.removeAllUserScripts()
        controller.addUserScript(script)
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStartLoad else { return }
        didStartLoad = true

        // WebAssembly is disabled under Lockdown Mode, so the realm cannot run at all. Say so
        // natively rather than letting the loader tell an iPhone player to "try the latest Chrome".
        if webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled {
            phase = .lockdown
            return
        }

        phase = record.isLinked ? .booting : .pairing(nil)
        webView.load(URLRequest(url: Self.realmURL))
    }

    /// Recovery is always a reload of the same view — never a new one, never a second `load()`.
    func retry() {
        phase = record.isLinked ? .booting : .pairing(nil)
        if webView.url == nil {
            webView.load(URLRequest(url: Self.realmURL))
        } else {
            webView.reload()
        }
    }

    // MARK: - Calling into the page

    /// Redeem a pairing code. The page posts `persist` before this resolves, so the Keychain is
    /// already written by the time we reload.
    func redeem(code: String) async throws -> String {
        // The rejection is caught INSIDE JavaScript. A promise that rejects across the bridge
        // arrives as an opaque WKError and the player would see nothing useful.
        // Built by concatenation rather than String(format:) — a stray % in a future edit of this
        // script would be read as a format specifier and corrupt the call.
        let js = """
        (async function () {
          try {
            var r = await window.CHIK_LINK.redeem(
        """
            + Self.jsString(code)
            + """
        );
            return { ok: true, wallet: r.wallet };
          } catch (e) {
            return { ok: false, error: String((e && e.message) || e) };
          }
        })()
        """
        let result = try await evaluate(js)

        guard let dict = result as? [String: Any] else {
            throw ShellError.message("The app could not reach the game. Try again.")
        }
        if dict["ok"] as? Bool == true, let wallet = dict["wallet"] as? String {
            // Reload so the realm signs in as the account we just linked. The injection has
            // already been rebuilt by the `persist` message.
            phase = .booting
            webView.reload()
            return wallet
        }
        throw ShellError.message(dict["error"] as? String ?? "That code did not work.")
    }

    /// Switch account. The page calls `location.reload()` itself, so do NOT await a reply — the
    /// navigation tears the JavaScript context down and the call would never return.
    func use(wallet: String) {
        phase = .booting
        let js = "window.CHIK_LINK.use(\(Self.jsString(wallet))); true;"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func forget(wallet: String) {
        let js = "window.CHIK_LINK.forget(\(Self.jsString(wallet))); true;"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func forgetAll() {
        webView.evaluateJavaScript("window.CHIK_LINK.forgetAll(); true;", completionHandler: nil)
    }

    // MARK: - Support and account deletion

    var appVersionDisplay: String { "\(appVersion) (\(appBuild))" }

    /// What support needs to act on a report: which build, which device, which account. No token.
    var supportBlob: String {
        """
        Chikoria \(appVersionDisplay)
        iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
        device: \(record.deviceId)
        account: \(activeWallet.isEmpty ? "not linked" : activeWallet)
        policy: \(policyIsLive ? "live" : "NOT CONFIRMED")
        """
    }

    /// App Review requires an in-app path to delete an account (5.1.1(v)).
    ///
    /// A Chikoria account IS a wallet, and this app deliberately cannot prove ownership of one —
    /// that is the whole design. So the device cannot authorise a destructive account action by
    /// itself: it asks, holding a link token that authorises play and nothing more, and the server
    /// decides. The route does not exist yet; IOS-APP.md carries the contract it needs.
    func requestAccountDeletion() {
        let js = """
        (async function () {
          try {
            var s = window.CHIK_LINK.status();
            var r = await fetch('https://api.chikimonsters.com/link/delete_account', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ wallet: s.wallet, device_id: s.deviceId, client: 'ios-app' })
            });
            return { ok: r.ok, status: r.status };
          } catch (e) { return { ok: false, error: String(e) }; }
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor in
                // Whatever the server does with the request, this device is done with the account.
                self?.forgetAll()
            }
        }
    }

    /// Every JavaScript body ends in a value. `evaluateJavaScript` on a body that returns
    /// `undefined` is reported as an error on some releases, which reads as a failure that is not.
    private func evaluate(_ js: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(js) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value ?? NSNull()) }
            }
        }
    }

    /// JSON-encode a string for safe interpolation into a script.
    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())     // ["…"] -> "…"
    }

    // MARK: - Messages from the page

    fileprivate func handle(message body: [String: Any]) {
        guard let kind = body["kind"] as? String else { return }

        switch kind {
        case "ready":
            // The ONLY proof the policy layer is live. If this never arrives, the injection did not
            // run — which in an app-bound-domains misconfiguration means chiki-ios.js stood down
            // and the wallet bridges are active. Fail closed on that, do not assume.
            policyIsLive = true
            let linked = body["linked"] as? Bool ?? false
            if case .pairing = phase, linked { phase = .booting }
            if !linked { phase = .pairing(nil) }

        case "persist":
            persist(body)

        case "linked":
            phase = .booting

        case "switched":
            phase = .booting

        case "unlinked":
            record = LinkKeychain.load() ?? record
            if !record.isLinked { phase = .pairing(nil) }

        case "link-rejected":
            // The token is dead server-side. Clear it and send the player back to pairing with a
            // reason, rather than leaving them on a screen that will never sign in.
            LinkKeychain.clearAccounts()
            record = LinkKeychain.load() ?? LinkRecord.fresh()
            installInjection()
            phase = .pairing("Your link to this account has ended. Pair again from the website.")

        case "stale-shell":
            phase = .staleShell

        case "paused":
            phase = .paused(body["message"] as? String ?? "Chikoria is down for maintenance.")

        case "progress":
            progress = body["percent"] as? Int ?? progress
            progressNote = body["note"] as? String ?? progressNote

        case "external-link":
            openExternal(body["url"] as? String)

        default:
            break
        }
    }

    /// Write the page's credential record to the Keychain and rebuild the injection.
    ///
    /// Treated as UNTRUSTED SHAPE, not as a schema: the handler is reachable from any script in the
    /// page world, so every field is validated rather than force-cast.
    private func persist(_ body: [String: Any]) {
        let deviceId = (body["deviceId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? record.deviceId
        let active = body["active"] as? String ?? ""
        let raw = body["accounts"] as? [[String: Any]] ?? []

        let accounts: [LinkRecord.Account] = raw.compactMap { entry in
            guard let wallet = entry["wallet"] as? String, !wallet.isEmpty,
                  let token = entry["token"] as? String, !token.isEmpty else { return nil }
            return LinkRecord.Account(
                wallet: wallet,
                token: token,
                label: entry["label"] as? String ?? "",
                linkedAt: (entry["linkedAt"] as? Double) ?? 0
            )
        }

        var next = record
        next.deviceId = deviceId
        next.active = accounts.contains(where: { $0.wallet == active }) ? active : (accounts.first?.wallet ?? "")
        next.accounts = accounts

        guard next != record else { return }
        record = next
        LinkKeychain.save(next)
        installInjection()      // see the comment there — this is not optional
    }

    /// Open a community link in the system browser, after re-checking it here.
    private func openExternal(_ raw: String?) {
        guard let raw,
              let url = URL(string: raw),
              url.scheme == "https",
              let host = url.host,
              Self.externalHosts.contains(host.lowercased())
        else {
            NSLog("[chikoria] refused external-link: \(raw ?? "nil")")
            return
        }
        UIApplication.shared.open(url)
    }
}

enum ShellError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

// MARK: - Navigation policy

extension ShellModel: WKNavigationDelegate {

    /// The backstop the web layer cannot provide. `location.href` assignment cannot be intercepted
    /// from script, and the Godot engine hands the compiled pack a bare `window.open` through
    /// `OS.shell_open`. This is where those stop.
    ///
    /// SAME-ORIGIN IS NOT ENOUGH. `/arena/` is the full SOL wager client and `/link/` carries a
    /// Phantom sign-in, and neither loads the policy layer. Only `/realm/` is safe.
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }

        // about:blank and friends appear during normal engine start-up.
        if url.scheme == "about" { return decisionHandler(.allow) }

        let ok = url.scheme == "https"
            && url.host?.lowercased() == Self.realmHost
            && url.path.hasPrefix(Self.realmPathPrefix)

        if !ok { NSLog("[chikoria] blocked navigation: \(url.absoluteString)") }

        // NOTE: the query string is never inspected or rewritten. The loader reloads itself with
        // ?swretry=1 to break a cross-origin-isolation deadlock, and a shell that "restored the
        // canonical URL" would strip it and loop forever.
        decisionHandler(ok ? .allow : .cancel)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if case .booting = self.phase, self.record.isLinked { self.phase = .playing }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.fail(error) }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.fail(error) }
    }

    /// The web content process was killed — almost always the memory ceiling on a phone.
    ///
    /// RELOAD THE SAME VIEW. The loader's own out-of-memory detector only fires when the page comes
    /// back with its boot flags still set in sessionStorage; it then drops the device to the
    /// lighter pack for 24 hours. A fresh web view would clear those flags, the detector would
    /// never fire, and the phone would retry the heavy pack and die again, forever.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            NSLog("[chikoria] web content process terminated — reloading the same view")
            webView.reload()
        }
    }

    @MainActor
    private func fail(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }

        let offline = ns.domain == NSURLErrorDomain && [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
        ].contains(ns.code)

        phase = .failed(offline
            ? "Chikoria needs a connection to load the realm. Check your network and try again."
            : "The realm could not be loaded. Try again in a moment.")
    }
}

// MARK: - UI delegate

extension ShellModel: WKUIDelegate {

    /// `window.open` from the page opens a window only if the app hands one back. Returning nil
    /// makes every `OS.shell_open` in the compiled pack a no-op, which is the whole point.
    nonisolated func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        NSLog("[chikoria] refused window.open: \(navigationAction.request.url?.absoluteString ?? "?")")
        return nil
    }
}

// MARK: - Message proxy

/// `WKUserContentController.add(_:name:)` retains its handler STRONGLY, and the controller is
/// retained by the configuration, which is retained by the web view, which the model owns. Adding
/// the model directly is a retain cycle that never releases the web view. This breaks it.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: ShellModel?

    init(_ target: ShellModel) {
        self.target = target
        super.init()
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "chikiLink", let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak target] in target?.handle(message: body) }
    }
}
