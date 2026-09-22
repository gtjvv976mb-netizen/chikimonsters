import Foundation
import Security

/// The device's Realm Link credential, held in the Keychain.
///
/// WHY THE KEYCHAIN AND NOT THE WEB VIEW. `realm/chiki-ios.js` writes nothing to `localStorage`
/// once the shell sets `keychain: true` — the shell is the store. That inversion exists because
/// WKWebView website data can be purged by the system, and a purge would take both the token and
/// the device id with it. The Keychain survives it, and survives an app reinstall-from-backup.
///
/// THE DEVICE ID IS PART OF THE CREDENTIAL, NOT A DERIVED VALUE. The backend binds a link token to
/// the `device_id` that redeemed it. If the id were regenerated — which is exactly what the web
/// layer used to do when `localStorage` was cleared — a restored token would arrive bound to a
/// device the server has never seen, and the restore would fail for the one event it exists to
/// survive. So the id is minted once, here, and never changes for the life of the install.
struct LinkRecord: Codable, Equatable {

    struct Account: Codable, Equatable {
        var wallet: String
        var token: String
        var label: String
        var linkedAt: Double
        /// True when the app made this account itself, rather than pairing to a wallet the player
        /// already had. It is what decides whether Account offers "Connect a wallet" — pairing
        /// means they have one already, and offering again would be nonsense.
        ///
        /// Optional with a default so a record written by an earlier build still decodes: a
        /// Keychain item survives app updates, and a non-optional new field would have made every
        /// existing install fail to load and look like being signed out.
        var appMade: Bool? = nil
    }

    var deviceId: String
    var active: String
    var accounts: [Account]

    static func fresh() -> LinkRecord {
        LinkRecord(deviceId: UUID().uuidString, active: "", accounts: [])
    }

    var isLinked: Bool { !accounts.isEmpty }

    var activeAccount: Account? {
        accounts.first(where: { $0.wallet == active }) ?? accounts.first
    }

    /// The shape `chiki-ios.js` expects on `window.CHIK_IOS_APP`. Tokens included — this is the
    /// injection, and it is the only place they are handed back to the page.
    func injectionPayload(deviceName: String, version: String, build: String) -> [String: Any] {
        [
            "deviceName": deviceName,
            "version": version,
            "build": build,
            "keychain": true,
            "deviceId": deviceId,
            "active": active,
            "accounts": accounts.map {
                ["wallet": $0.wallet, "token": $0.token, "label": $0.label, "linkedAt": $0.linkedAt,
                 "appMade": $0.appMade ?? false]
            },
        ]
    }
}

/// Reads and writes exactly one Keychain item. Small on purpose: everything that can go wrong with
/// the Keychain goes wrong in one place.
enum LinkKeychain {

    private static let service = "com.chikimonsters.realm.link"
    private static let account = "credential"

    /// `kSecAttrAccessibleAfterFirstUnlock`, deliberately:
    ///   * not `WhenUnlocked` — the app can be relaunched by the system while the device is locked,
    ///     and a read that fails there would look to the player like being signed out.
    ///   * not `...ThisDeviceOnly` would allow an encrypted-backup restore onto a new phone; we do
    ///     NOT want that, because the record carries a device id the server has bound a token to.
    ///     Two phones presenting one device id is a support problem, so this stays device-only.
    ///   * never `kSecAttrSynchronizable` — same reason, doubled.
    private static let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// Load the record, minting a fresh one (and saving it) the first time the app runs.
    static func loadOrCreate() -> LinkRecord {
        if let existing = load() { return existing }
        let fresh = LinkRecord.fresh()
        save(fresh)
        return fresh
    }

    static func load() -> LinkRecord? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                NSLog("[chikoria] keychain read failed: \(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(LinkRecord.self, from: data)
    }

    /// Replace the stored record wholesale. `persist` from the page is authoritative.
    @discardableResult
    static func save(_ record: LinkRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }

        // Update first; add only if it is not there. SecItemAdd on an existing item returns
        // errSecDuplicateItem, and treating that as failure is the classic Keychain bug.
        let updated = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return true }

        if updated == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = accessible
            let added = SecItemAdd(add as CFDictionary, nil)
            if added == errSecSuccess { return true }
            NSLog("[chikoria] keychain add failed: \(added)")
            return false
        }

        NSLog("[chikoria] keychain update failed: \(updated)")
        return false
    }

    /// Forget the credentials but KEEP the device id — it identifies the install, not the account,
    /// and regenerating it on every unlink would leak a new device into the player's device list
    /// each time they re-paired.
    static func clearAccounts() {
        var record = load() ?? LinkRecord.fresh()
        record.accounts = []
        record.active = ""
        save(record)
    }

    /// Only for an "erase everything" control. The next launch mints a new device id.
    static func destroy() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("[chikoria] keychain delete failed: \(status)")
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
