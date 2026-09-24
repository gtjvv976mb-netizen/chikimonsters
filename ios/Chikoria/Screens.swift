import SwiftUI
import WebKit

// MARK: - Palette

/// The site's own colours, so the native screens and the loading screen read as one app.
enum Ink {
    static let bg = Color(red: 0.043, green: 0.071, blue: 0.125)      // #0b1220
    static let panel = Color(red: 0.071, green: 0.110, blue: 0.188)   // #121c30
    static let line = Color(red: 0.141, green: 0.200, blue: 0.306)    // #24334e
    static let text = Color(red: 0.918, green: 0.949, blue: 1.0)      // #eaf2ff
    static let dim = Color(red: 0.576, green: 0.651, blue: 0.769)     // #93a6c4
    static let gold = Color(red: 1.0, green: 0.827, blue: 0.302)      // #ffd34d
    static let bad = Color(red: 0.973, green: 0.443, blue: 0.443)     // #f87171
}

// MARK: - The web view host

/// Hands SwiftUI the model's existing web view. It NEVER creates one — see ShellModel.
struct RealmWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Root

struct RootView: View {
    @StateObject private var model = ShellModel()
    @State private var showAccount = false

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()

            // The web view stays mounted under every overlay. Tearing it down to show a screen
            // would restart a multi-minute boot and blind the loader's own recovery guards.
            RealmWebView(webView: model.webView)
                .ignoresSafeArea()
                .opacity(model.phase == .playing || model.phase == .booting ? 1 : 0)
                .accessibilityHidden(model.phase != .playing)

            switch model.phase {
            case .booting:
                if !model.isLinked { PairingView(model: model, reason: nil) }
            case .pairing(let reason):
                PairingView(model: model, reason: reason)
            case .playing:
                EmptyView()
            case .failed(let message):
                OfflineScreen(model: model, message: message)
            case .paused(let message):
                MessageScreen(title: "Back shortly", message: message,
                              action: ("Try again", { model.retry() }))
            case .staleShell:
                MessageScreen(
                    title: "Update Chiki Monsters",
                    message: "This version of the app is older than the realm supports. Update from the App Store to keep playing.",
                    action: nil)
            case .lockdown:
                MessageScreen(
                    title: "Lockdown Mode is on",
                    message: "Chiki Monsters’ 3D world needs WebAssembly, which Lockdown Mode switches off. "
                        + "You can allow Chiki Monsters in Settings → Privacy & Security → Lockdown Mode → Configure App Access.",
                    action: nil)
            }

            // Over the web view until the page proves it is alive — see ShellModel.pageAlive.
            if model.isLinked && (model.phase == .booting || model.phase == .playing) && !model.pageAlive {
                BootCover(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .task { model.start() }
        .sheet(isPresented: $showAccount) { AccountView(model: model) }
        .overlay(alignment: .bottom) {
            // The web loader draws its own bar, so this does not duplicate it. It carries the one
            // thing the page cannot know and the player would otherwise only discover on their
            // bill: that this is a large download and they are not on Wi-Fi.
            if model.phase == .booting && model.isMetered {
                MeteredBanner(percent: model.progress)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: model.isMetered)
        .overlay(alignment: .topTrailing) {
            if model.phase == .playing {
                Button { showAccount = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Ink.gold)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(.top, 6)
                .padding(.trailing, 10)
                .accessibilityLabel("Account")
            }
        }
    }
}

// MARK: - Pairing

/// The one screen that must exist natively: nothing in the web repo draws it.
struct PairingView: View {
    @ObservedObject var model: ShellModel
    let reason: String?

    init(model: ShellModel, reason: String?) {
        self.model = model
        self.reason = reason
        _hasCode = State(initialValue: reason != nil)
    }

    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    /// false: the welcome screen, whose primary action makes an account. true: the code box, for a
    /// player who already has one. Starts false — the player who needs nothing is the common case,
    /// and the one this screen used to have no path for at all.
    ///
    /// EXCEPT WHEN WE ARRIVED HERE WITH A REASON. A reason means a credential was rejected: the
    /// player HAD an account a moment ago. Opening on "Create an account" would invite them to tap
    /// it, and that would mint a second, empty, unrecoverable account while the first one sat
    /// there — the worst outcome on this screen. So a reason opens the code box instead, where the
    /// player can get back to the account they already have.
    @State private var hasCode: Bool
    @FocusState private var focused: Bool

    /// `chiki-ios.js` uppercases the code and strips everything that is not 0-9 or A-Z, then
    /// refuses anything under six characters. Do the same here so the player sees the code they
    /// are actually sending, and so the keyboard cannot produce something that will be rejected.
    private var cleaned: String {
        String(code.uppercased().filter { $0.isASCII && ($0.isNumber || $0.isLetter) }.prefix(12))
    }
    private var canSubmit: Bool { cleaned.count >= 6 && !busy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(hasCode ? "Link your account" : "Welcome to Chiki Monsters")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Ink.text)

                if let reason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Ink.bad)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 12))
                }

                // THE DEFAULT PATH IS THE ONE THAT NEEDS NOTHING.
                //
                // This screen used to open straight onto a code box, and the code could only come
                // from a website that required a crypto wallet. For a player who had just
                // downloaded the app and owned no wallet — which is almost all of them — the first
                // screen of the game was an instruction to go and get one somewhere else. That is a
                // dead end for the player and a guideline 3.1.1 problem for the build.
                //
                // So: make an account, here, in one tap. Pairing is still offered, underneath, for
                // the players who do have an account already and came looking for it.
                if !hasCode {
                    Text("Start playing straight away. Your island, your creatures and everything you "
                         + "gather are saved to your account and waiting whenever you come back.")
                        .foregroundStyle(Ink.dim)

                    if let error {
                        Text(error).foregroundStyle(Ink.bad).font(.callout)
                    }

                    Button(action: create) {
                        HStack {
                            if busy { ProgressView().tint(.black) }
                            Text(busy ? "Creating…" : "Create an account").fontWeight(.heavy)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    .background(busy ? Ink.gold.opacity(0.4) : Ink.gold, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
                    .disabled(busy)

                    Text("No email, no password — the account lives on this iPhone. You can back it "
                         + "up to your chikimonsters.com account later from Account, so you keep it "
                         + "if you ever lose this phone.")
                        .font(.footnote)
                        .foregroundStyle(Ink.dim)

                    Divider().overlay(Ink.line).padding(.vertical, 4)

                    Button("I already have a Chiki Monsters account") { withAnimation { hasCode = true } }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Ink.gold)

                    Spacer(minLength: 0)
                }

                if hasCode {
                Text("Chiki Monsters on this iPhone plays the account you already have. "
                     + "Everything you own comes with you, and everything you gather here is waiting when you get back.")
                    .foregroundStyle(Ink.dim)

                VStack(alignment: .leading, spacing: 10) {
                    Text("1 · On a computer or tablet, open **chikimonsters.com/link**")
                    Text("2 · Sign in there and press **New code**")
                    Text("3 · Type the code below")
                }
                .font(.callout)
                .foregroundStyle(Ink.dim)

                TextField("", text: $code, prompt: Text("ABCD 1234").foregroundColor(Ink.dim))
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .kerning(6)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
                    .foregroundStyle(Ink.gold)

                if let error {
                    Text(error).foregroundStyle(Ink.bad).font(.callout)
                }

                Button(action: submit) {
                    HStack {
                        if busy { ProgressView().tint(.black) }
                        Text(busy ? "Linking…" : "Link this iPhone").fontWeight(.heavy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .background(canSubmit ? Ink.gold : Ink.gold.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
                .disabled(!canSubmit)

                // A player who has only a phone cannot mint a code at all: the website needs a
                // wallet. Saying so here is kinder than letting them hunt for it.
                Text("The code comes from chikimonsters.com, where you sign in. "
                     + "It lasts about ten minutes and works once.")
                    .font(.footnote)
                    .foregroundStyle(Ink.dim)

                // (No "still connecting" note here any more: the realm does not load until there is
                // an account, and creating or linking one does not need it — see ShellModel.start.)
                Button("Back") { withAnimation { hasCode = false; error = nil } }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.dim)
                }
            }
            .padding(24)
        }
        .background(Ink.bg)
        // The single-parameter form on purpose: the two-parameter onChange is iOS 17, and this
        // target is 16.0. Focusing the field only when the code box is the thing on screen —
        // opening the keyboard over the welcome screen would cover its primary button.
        .onChange(of: hasCode) { now in focused = now }
    }

    private func create() {
        busy = true
        error = nil
        Task {
            do {
                _ = try await model.createAccount()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                _ = try await model.redeem(code: cleaned)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Account

struct AccountView: View {
    @ObservedObject var model: ShellModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var confirmUnlink = false
    @State private var deleteNote: String?
    @State private var claim: String?
    @State private var claimSeconds = 0
    @State private var claimBusy = false
    @State private var claimError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Playing as") {
                    ForEach(model.record.accounts, id: \.wallet) { account in
                        Button {
                            model.use(wallet: account.wallet)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(short(account.wallet)).fontWeight(.semibold)
                                    if !account.label.isEmpty {
                                        Text(account.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if account.wallet == model.activeWallet {
                                    Image(systemName: "checkmark").foregroundStyle(Ink.gold)
                                }
                            }
                        }
                    }
                }

                // ONLY FOR AN ACCOUNT THE APP MADE. A player who paired already has a wallet, and
                // offering to connect one would be nonsense; the policy layer answers `walletless`
                // from what it wrote down when it created the account.
                if model.activeIsWalletless {
                    Section {
                        if let claim {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(claim).font(.system(size: 30, weight: .bold, design: .monospaced))
                                    .kerning(6).frame(maxWidth: .infinity).foregroundStyle(Ink.gold)
                                Text("1 · On the device you use for chikimonsters.com, open **chikimonsters.com/link**\n"
                                     + "2 · Sign in to your account there\n"
                                     + "3 · Enter this code under **Connect an app account**")
                                    .font(.callout).foregroundStyle(.secondary)
                                // A code that has quietly expired looks exactly like a live one,
                                // and the failure it causes appears on the OTHER device — so say
                                // how long it has, and offer a fresh one rather than making the
                                // player work out that that is what they need.
                                Text("This code lasts about \(max(1, claimSeconds / 60)) minutes and works once.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                HStack(spacing: 16) {
                                    Button("Copy code") { UIPasteboard.general.string = claim }
                                    Button("New code") { self.claim = nil; connect() }
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button(claimBusy ? "Getting a code…" : "Back up this account") { connect() }
                                .disabled(claimBusy)
                        }
                        if let claimError {
                            Text(claimError).foregroundStyle(Ink.bad).font(.callout)
                        }
                    } header: {
                        Text("Back up")
                    } footer: {
                        // Says what it costs and what it buys, and points at no destination the
                        // player has not already got. The app never opens this link itself.
                        Text("This account was made on this iPhone, and only this iPhone can open it. "
                             + "Backing it up moves it, and everything on it, onto your chikimonsters.com "
                             + "account, so you keep it if you lose this phone. It is a one-way change.")
                    }
                }

                Section {
                    Button("Link another account") { confirmUnlink = true }
                    Button("Unlink this iPhone", role: .destructive) { confirmUnlink = true }
                } footer: {
                    // THE FOOTER IS NOT THE SAME SENTENCE FOR BOTH KINDS OF ACCOUNT, because the
                    // button does not do the same thing. Unlinking a PAIRED device removes this
                    // phone's access and nothing else — the account is a wallet and the wallet
                    // still exists. Unlinking an account the APP made destroys it: the credential
                    // on this device is the only way into it that will ever exist, nothing can
                    // sign for its address, and there is no code to link again with. The old copy
                    // promised the reassuring version to both.
                    Text(model.activeIsWalletless
                         ? "This account was made on this iPhone and the only key to it is here. "
                           + "Unlinking loses it for good. Back it up first if you want to keep it."
                         : "Unlinking removes this device’s access. Your account and everything on it "
                           + "are untouched, and you can link again with a new code.")
                }

                Section {
                    Button("Delete my account…", role: .destructive) { confirmDelete = true }
                    if let deleteNote {
                        Text(deleteNote).font(.callout).foregroundStyle(.secondary)
                    }
                } footer: {
                    // App Review requires an in-app deletion path for any app with accounts.
                    // The sentence differs by account kind and the difference is not cosmetic: an
                    // account the app made has no wallet and cannot hold anything on-chain, so
                    // promising that its on-chain assets are safe describes assets that do not
                    // exist and quietly implies its progress might survive somewhere. It does not.
                    Text(model.activeIsWalletless
                         ? "This account was made in the app, so deleting it removes everything on "
                           + "it. Nothing is kept anywhere else."
                         : "Deleting removes your Chiki Monsters progress from our servers.")
                }

                Section("Support") {
                    LabeledContent("App version", value: model.appVersionDisplay)
                    LabeledContent("Device ID", value: short(model.record.deviceId))
                    Button("Copy support details") { UIPasteboard.general.string = model.supportBlob }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Delete your Chiki Monsters account?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            _ = try await model.requestAccountDeletion()
                            deleteNote = "Your account is scheduled for deletion. Signing in again "
                                + "before it completes cancels it."
                            dismiss()
                        } catch {
                            // Say so. The old code signed the device out whatever the server
                            // answered, which showed a deletion that had not happened.
                            deleteNote = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text(model.activeIsWalletless
                     ? "This asks us to delete this account and everything on it, permanently. "
                       + "It was made in the app, so there is nothing kept anywhere else."
                     : "This asks us to delete your Chiki Monsters progress permanently. It cannot be undone.")
            }
            .alert(model.activeIsWalletless ? "Lose this account?" : "Unlink this iPhone?",
                   isPresented: $confirmUnlink) {
                Button("Cancel", role: .cancel) {}
                Button(model.activeIsWalletless ? "Lose it" : "Unlink", role: .destructive) {
                    model.forgetAll()
                    dismiss()
                }
            } message: {
                Text(model.activeIsWalletless
                     ? "This account was made on this iPhone and the key to it is only here. "
                       + "Unlinking loses it permanently — there is no code that can bring it back. "
                       + "If you want to keep it, back it up first."
                     : "This removes this device’s access. Your account is untouched and you can "
                       + "link again with a new code from the website.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func connect() {
        claimBusy = true
        claimError = nil
        Task {
            do {
                let got = try await model.connectWallet()
                claim = got.code
                claimSeconds = got.seconds
            } catch {
                claimError = error.localizedDescription
            }
            claimBusy = false
        }
    }

    private func short(_ s: String) -> String {
        s.count > 12 ? "\(s.prefix(4))…\(s.suffix(4))" : s
    }
}

// MARK: - Offline

/// What the app shows when it cannot reach the network.
///
/// THIS SCREEN IS THE GUIDELINE 4.2 TEST. Reviewers check for a repackaged website by turning on
/// Airplane Mode; a blank web view or a browser error is what gets an app flagged. So this is
/// native, and it carries real remembered state rather than only an apology — who is signed in,
/// when they last played, and whether the world is already downloaded and waiting.
///
/// It is honest about the limit: the game itself needs the server to sign in, so this does not
/// pretend the world can be entered offline.
struct OfflineScreen: View {
    @ObservedObject var model: ShellModel
    let message: String

    private var lastPlayedText: String? {
        guard let d = model.lastKnown.lastPlayed else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundStyle(Ink.gold)
                .padding(.bottom, 14)

            Text("You’re offline")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Ink.text)
            Text(message)
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 6)

            // The remembered part. Nothing here needs the network.
            VStack(alignment: .leading, spacing: 12) {
                if !model.lastKnown.wallet.isEmpty {
                    Row(icon: "person.crop.circle", title: "Signed in",
                        detail: short(model.lastKnown.wallet))
                }
                if let lastPlayedText {
                    Row(icon: "clock", title: "Last played", detail: lastPlayedText)
                }
                Row(icon: model.lastKnown.worldDownloaded ? "checkmark.circle" : "arrow.down.circle",
                    title: "The world",
                    detail: model.lastKnown.worldDownloaded
                        ? "Downloaded and ready on this iPhone"
                        : "Not downloaded yet — needs a connection once")
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
            .padding(.top, 22)
            .padding(.horizontal, 24)

            Button { model.retry() } label: {
                Text("Try again").fontWeight(.heavy).padding(.horizontal, 30).padding(.vertical, 13)
            }
            .background(Ink.gold, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.black)
            .padding(.top, 20)

            Text("Chiki Monsters needs a connection to sign in to your account.")
                .font(.footnote)
                .foregroundStyle(Ink.dim)
                .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
    }

    private func short(_ s: String) -> String {
        s.count > 12 ? "\(s.prefix(4))…\(s.suffix(4))" : s
    }

    private struct Row: View {
        let icon: String, title: String, detail: String
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Ink.gold).frame(width: 22)
                Text(title).foregroundStyle(Ink.dim)
                Spacer(minLength: 8)
                Text(detail).foregroundStyle(Ink.text).fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
            }
            .font(.callout)
        }
    }
}

// MARK: - Metered banner

/// Shown only on a connection the player pays for by the megabyte.
///
/// The numbers are honest about which pack is actually being fetched: the loader drops to the
/// lighter 174 MB pack on a metered connection rather than the 313 MB one, so quoting the larger
/// figure here would be wrong as well as alarming.
struct MeteredBanner: View {
    let percent: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Ink.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Building the realm over mobile data")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.text)
                Text("Using the lighter world — about 175 MB, once. Wi-Fi is kinder to your plan.")
                    .font(.caption2)
                    .foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 0)
            Text("\(percent)%")
                .font(.footnote.monospacedDigit().weight(.bold))
                .foregroundStyle(Ink.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Ink.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line))
        .padding(.horizontal, 16)
    }
}

// MARK: - Boot cover

/// What the player sees between "the realm is loading" and the loader drawing its own screen.
///
/// It exists because that gap used to be a bare web view, and a WKWebView that has not painted —
/// or whose content process has died — is plain white. A tester who tapped "Create an account"
/// saw white and nothing else, with no way to tell a slow network from a crash. This says which
/// it is, and if the page has still not come alive after a while it shows the details worth
/// sending to support, and a way to try again.
struct BootCover: View {
    @ObservedObject var model: ShellModel
    @State private var slow = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Chiki Monsters")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Ink.gold)
            if !model.bootStalled {
                ProgressView().tint(Ink.gold)
            }
            Text(model.bootStage)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if slow || model.bootStalled {
                // Re-rendered every second so the "waiting" count moves.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(model.bootDiagnostics)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Ink.dim)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
                HStack(spacing: 14) {
                    Button { model.retry() } label: {
                        Text("Try again").fontWeight(.heavy).padding(.horizontal, 24).padding(.vertical, 11)
                    }
                    .background(Ink.gold, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
                    Button("Copy details") {
                        UIPasteboard.general.string = model.bootDiagnostics + "\n" + model.supportBlob
                    }
                    .foregroundStyle(Ink.gold)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg.ignoresSafeArea())
        // Restarts with every new load, so "slow" means slow THIS time.
        .task(id: model.loadStartedAt) {
            slow = false
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled { slow = true }
        }
    }
}

// MARK: - Message screen

struct MessageScreen: View {
    let title: String
    /// NOT named `body` — that is `View`'s own requirement, and the collision does not compile.
    let message: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: action.1) {
                    Text(action.0).fontWeight(.heavy).padding(.horizontal, 26).padding(.vertical, 13)
                }
                .background(Ink.gold, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
    }
}
