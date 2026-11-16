import SwiftUI
import VisionKit
import Security
import HudCore

/// Remote Connect, opened by holding the gear: scan the code on the Android phone, and this
/// phone works its glasses until disconnected.
struct RemoteConnectView: View {
    @ObservedObject var controller: HudController
    @State private var scanning = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Picker("Mode", selection: Binding(get: { controller.remoteHosting },
                                                  set: { controller.setRemoteHosting($0) })) {
                    Text("REMOTE").tag(false)
                    Text("HOST").tag(true)
                }
                .pickerStyle(.segmented)
                Text(controller.remoteHosting
                     ? "This iPhone runs the apps; the Android phone shows them on its glasses."
                     : "This iPhone works the Android phone's apps, on its glasses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                status
                if scanning {
                    QRScanner { payload in
                        if controller.pair(with: payload) {
                            scanning = false
                            problem = nil
                        } else {
                            problem = "That is not a TheHud code."
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, maxHeight: 360)
                } else {
                    Text("On the Android phone, hold its settings button to show its code, then scan it here. Both phones need to be on the same Wi-Fi.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                Spacer()
                VStack(spacing: 12) {
                    if QRScanner.isAvailable {
                        Button(scanning ? "Stop scanning" : "Scan the code") { scanning.toggle() }
                            .buttonStyle(.borderedProminent)
                            .tint(HudTheme.accent)
                    }
                    if controller.remoteStatus != .off {
                        Button("Disconnect", role: .destructive) { controller.forgetRemote() }
                    }
                }
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle("Remote Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { controller.showingRemoteConnect = false }
                }
            }
            .onAppear { scanning = controller.remoteStatus == .off && QRScanner.isAvailable }
        }
        .preferredColorScheme(.dark)
    }

    private var status: some View {
        let (text, colour): (String, Color) = switch controller.remoteStatus {
        case .off: ("NOT CONNECTED", HudTheme.inkFaint)
        case .connecting: ("LOOKING FOR THE ANDROID PHONE", HudTheme.inkDim)
        case let .connected(name) where controller.remoteHosting:
            ("SHOWING THIS IPHONE ON \(name.uppercased())'S GLASSES", HudTheme.accent)
        case let .connected(name): ("WORKING \(name.uppercased())'S GLASSES", HudTheme.accent)
        case .refused: ("ITS CODE CHANGED: SCAN IT AGAIN", .red)
        }
        return Text(text)
            .font(HudTheme.mont(12, .black))
            .tracking(2)
            .foregroundStyle(colour)
            .multilineTextAlignment(.center)
    }
}

/// The camera, reading QR codes, with VisionKit's own highlighting.
struct QRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.found = found
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        private var last = ""

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                guard let payload = code.payloadStringValue, payload != last else { continue }
                last = payload
                found(payload)
            }
        }
    }
}

/// The pairing, in the keychain: it holds the key that lets this phone work the other's glasses.
enum RemotePairingStore {
    private static let account = "remote-connect"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.thehud.remote-connect",
         kSecAttrAccount as String: account]
    }

    static func load() -> RemotePairing? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(RemotePairing.self, from: data)
    }

    static func save(_ pairing: RemotePairing?) {
        SecItemDelete(query as CFDictionary)
        guard let pairing, let data = try? JSONEncoder().encode(pairing) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
