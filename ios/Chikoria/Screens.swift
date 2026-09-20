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
                    title: "Update Chikoria",
                    message: "This version of the app is older than the realm supports. Update from the App Store to keep playing.",
                    action: nil)
            case .lockdown:
                MessageScreen(
                    title: "Lockdown Mode is on",
                    message: "Chikoria’s 3D world needs WebAssembly, which Lockdown Mode switches off. "
                        + "You can allow Chikoria in Settings → Privacy & Security → Lockdown Mode → Configure App Access.",
                    action: nil)
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

    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
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
                Text("Link your account")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Ink.text)

                Text("Chikoria on this iPhone plays the account you already have. "
                     + "Everything you own comes with you, and everything you gather here is waiting when you get back.")
                    .foregroundStyle(Ink.dim)

                if let reason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Ink.bad)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("1 · On a computer or tablet, open **chikimonsters.com/link**")
                    Text("2 · Sign in there and press **New code**")
                    Text("3 · Type the code below")
                }
                .font(.callout)
                .foregroundStyle(Ink.dim)

                TextField("", text: $code, prompt: Text("ABCD 1234").foregroundStyle(Ink.dim))
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
                Text("The code has to come from the website, where your wallet is. "
                     + "It lasts about ten minutes and works once.")
                    .font(.footnote)
                    .foregroundStyle(Ink.dim)

                if !model.policyIsLive {
                    // 'ready' has not arrived. Either the page has not loaded yet, or — the case
                    // worth surfacing — the injection did not run and the policy layer stood down.
                    Label("Still connecting to the realm…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(Ink.dim)
                }
            }
            .padding(24)
        }
        .background(Ink.bg)
        .onAppear { focused = true }
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

                Section {
                    Button("Link another account") {
                        model.forgetAll()   // returns to pairing; the realm reloads unlinked
                        dismiss()
                    }
                    Button("Unlink this iPhone", role: .destructive) {
                        model.forgetAll()
                        dismiss()
                    }
                } footer: {
                    Text("Unlinking removes this device’s access. Your account and everything on it "
                         + "are untouched, and you can link again with a new code.")
                }

                Section {
                    Button("Delete my account…", role: .destructive) { confirmDelete = true }
                } footer: {
                    // App Review requires an in-app deletion path for any app with accounts.
                    // A Chikoria account IS a wallet, which this app cannot prove ownership of —
                    // so deletion is a request the server honours, not something the device does.
                    Text("Deleting removes your Chikoria progress from our servers. Assets held "
                         + "on-chain belong to your wallet and are not affected.")
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
            .alert("Delete your Chikoria account?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { model.requestAccountDeletion() }
            } message: {
                Text("This asks us to delete your Chikoria progress permanently. It cannot be undone. "
                     + "Assets held on-chain stay in your wallet.")
            }
        }
        .preferredColorScheme(.dark)
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

            Text("Chikoria needs a connection to sign in to your account.")
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
                Button(action.1) {
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
