import SwiftUI
import VisionKit
import Security
import HudCore

/// Remote Connect, opened by holding the gear: scan the code on the Android phone, and this
/// phone works its glasses until disconnected. One card says where things are; the buttons under
/// it are only the ones that state has.
struct RemoteConnectView: View {
    @ObservedObject var controller: HudController
    /// A new code wanted while paired: the scanner over the card's advice.
    @State private var rescanning = false
    @State private var problem: String?

    private var paired: Bool { controller.remoteStatus != .off }
    private var refused: Bool { controller.remoteStatus == .refused }
    private var showsScanner: Bool { QRScanner.isAvailable && (!paired || refused || rescanning) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
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
                card
                if showsScanner {
                    QRScanner { payload in
                        if controller.pair(with: payload) {
                            rescanning = false
                            problem = nil
                        } else {
                            problem = "That is not a TheHud code."
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, maxHeight: 340)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                buttons.controlSize(.large)
            }
            .padding(20)
            .navigationTitle("Remote Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { controller.showingRemoteConnect = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Where things are, and what to do about it.
    private var card: some View {
        let looking = controller.remoteStatus == .connecting
        let (title, detail, colour): (String, String, Color) = switch controller.remoteStatus {
        case .off:
            ("NOT CONNECTED",
             QRScanner.isAvailable
                ? "On the Android phone, hold its settings button to show its code, and scan it here."
                : "This iPhone can't scan codes.",
             HudTheme.inkDim)
        case .connecting:
            (controller.remoteProblem?.title ?? "LOOKING FOR THE ANDROID PHONE",
             controller.remoteProblem?.detail ?? "Both phones need to be on the same Wi-Fi, with TheHud open on the Android phone.",
             controller.remoteProblem == nil ? HudTheme.ink : .orange)
        case let .connected(name):
            (controller.remoteHosting ? "SHOWING THIS IPHONE ON \(name.uppercased())'S GLASSES"
                                      : "WORKING \(name.uppercased())'S GLASSES",
             controller.remoteHosting ? "The apps run here; the glasses show them over Wi-Fi."
                                      : "Everything on this phone now works the Android phone's glasses.",
             HudTheme.accent)
        case .refused:
            ("ITS CODE CHANGED", "The Android phone shows a new code: scan it.", .red)
        }
        return HStack(alignment: .top, spacing: 14) {
            Group {
                if looking {
                    ProgressView().tint(colour)
                } else {
                    Image(systemName: controller.remoteStatus == .off ? "qrcode"
                          : refused ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(colour)
                }
            }
            .font(.system(size: 22, weight: .semibold))
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(HudTheme.mont(13, .black))
                    .tracking(1.5)
                    .foregroundStyle(colour)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Only what this state can do.
    @ViewBuilder private var buttons: some View {
        VStack(spacing: 12) {
            switch controller.remoteStatus {
            case .off:
                EmptyView()
            case .connecting:
                if controller.remoteProblem == .localNetworkOff {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HudTheme.accent)
                }
                if QRScanner.isAvailable {
                    Button(rescanning ? "Keep the code I have" : "Scan a new code") { rescanning.toggle() }
                        .buttonStyle(.bordered)
                }
                Button("Stop looking", role: .destructive) { forget() }
            case .connected:
                Button("Disconnect", role: .destructive) { forget() }
                    .buttonStyle(.bordered)
            case .refused:
                Button("Forget this phone", role: .destructive) { forget() }
            }
        }
    }

    private func forget() {
        rescanning = false
        problem = nil
        controller.forgetRemote()
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
