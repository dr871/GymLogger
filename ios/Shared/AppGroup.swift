import Foundation

/// Where the app and the widget meet.
///
/// The identifier is **discovered at runtime, not trusted from the source**,
/// and that is the whole point of this file. Installing with a free Apple ID
/// rewrites identifiers at signing time — SideStore appends the team ID to the
/// bundle identifier, and the app group it registers is the one it chose, not
/// the one written in our entitlements. Hardcoding `group.com.hellorogers.…`
/// would work in the simulator, fail silently on the phone, and look exactly
/// like "app groups don't work on free accounts" when in fact they do.
///
/// The truth is in the provisioning profile the signer embedded in the bundle.
/// The app and the widget each carry their own, both naming the same group, so
/// both arrive at the same string whatever it turned out to be.
enum AppGroup {

    /// What the entitlements file asks for. Used in the simulator, where there
    /// is no profile to read and the container is granted on the strength of
    /// the entitlement alone.
    static let declared = "group.com.hellorogers.gymlogger"

    static let identifier: String = fromProvisioningProfile() ?? declared

    /// The embedded profile is a CMS blob with a plain XML plist inside it.
    /// Finding that plist is enough; nothing here needs the signature.
    private static func fromProvisioningProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let start = raw.range(of: Data("<?xml".utf8)),
              let end = raw.range(of: Data("</plist>".utf8))
        else { return nil }

        let xml = raw[start.lowerBound..<end.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil),
              let root = plist as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        return groups.first
    }

    /// nil when the group wasn't granted — the signer stripped it, or this is a
    /// build with no entitlement at all. Callers handle nil rather than force
    /// it: on the phone this is the difference between a widget that says
    /// "Open GymLogger" and one that crashes.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The one file the app writes and the widget reads.
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget.json")
    }

    // MARK: - The two sides

    /// Best effort: a snapshot that can't be written costs the widget its
    /// freshness, and is never worth failing a save over.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL,
              let encoded = try? WidgetSnapshot.encoder().encode(snapshot) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let raw = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decoder().decode(WidgetSnapshot.self, from: raw)
    }
}
