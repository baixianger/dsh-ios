import SwiftUI
import VisionKit

struct DshNetworkPairingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairingURL = ""
    @State private var isPairing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    PairingCodeScanner(handlePayload: handlePayload)
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .compositingGroup()
                        .clipShape(.rect(cornerRadius: 16))
                } else {
                    ContentUnavailableView(
                        "此设备无法使用相机扫描",
                        systemImage: "qrcode.viewfinder",
                        description: Text("可以在下方粘贴配对链接。")
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("在 DSH Server 的 Shell 运行：")
                        .font(.subheadline)
                    Text("npx dsh-network pair --url https://your-server")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("二维码有效 5 分钟且只能使用一次。浏览器和 DSH iOS 使用同一种二维码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("https://server/dsh-network/connect?ticket=…", text: $pairingURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button("配对", systemImage: "link.badge.plus", action: pairTypedURL)
                    .buttonStyle(.borderedProminent)
                    .disabled(isPairing || URL(string: pairingURL) == nil)

                if isPairing { ProgressView("正在配对…") }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .navigationTitle("扫描 Server 二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func pairTypedURL() {
        guard let url = URL(string: pairingURL) else { return }
        pair(url)
    }

    private func handlePayload(_ payload: String) {
        guard !isPairing, let url = URL(string: payload) else { return }
        pairingURL = payload
        pair(url)
    }

    private func pair(_ url: URL) {
        isPairing = true
        errorMessage = nil
        Task {
            do {
                try await model.pairNetworkServer(scannedURL: url)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPairing = false
            }
        }
    }
}

private struct PairingCodeScanner: UIViewControllerRepresentable {
    let handlePayload: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(handlePayload: handlePayload)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let handlePayload: (String) -> Void

        init(handlePayload: @escaping (String) -> Void) {
            self.handlePayload = handlePayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                handlePayload(payload)
                break
            }
        }
    }
}
