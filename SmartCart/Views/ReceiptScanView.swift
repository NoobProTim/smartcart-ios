// ReceiptScanView.swift — SmartCart/Views/ReceiptScanView.swift
import SwiftUI
import PhotosUI
import AVFoundation

struct ReceiptScanView: View {

    @State private var showCamera           = false
    @State private var showPhotoPicker      = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var scanResult: ReceiptScanResult? = nil
    @State private var isScanning           = false
    @State private var errorMessage: String? = nil
    // P1-B: shown when camera permission is denied/restricted
    @State private var showPermissionSheet  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "receipt")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                Text("Scan a receipt to track what you buy and what you paid.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)

                if isScanning { ProgressView("Scanning…") }

                if let err = errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button {
                        // P1-B: Check permission before presenting camera.
                        checkCameraPermissionAndPresent()
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 40)
                    .onChange(of: pickerItem) { _, newItem in
                        guard let newItem else { return }
                        Task { await loadAndScan(item: newItem) }
                    }
                }
                Spacer()
            }
            .navigationTitle("Scan Receipt")
            // P1-H: .sheet(item:) uses UUID-backed Identifiable — no hash collision.
            .sheet(item: $scanResult) { result in
                ReceiptReviewView(
                    items: result.items.map { item in
                        ParsedReceiptItem(
                            rawName: item.nameRaw,
                            normalisedName: item.nameNormalised,
                            parsedPrice: item.price,
                            confidence: item.confidence >= 0.8 ? .high : .medium
                        )
                    },
                    isPresented: Binding(
                        get: { scanResult != nil },
                        set: { if !$0 { scanResult = nil } }
                    )
                )
            }
            // P1-B: Camera permission denied sheet.
            .sheet(isPresented: $showPermissionSheet) {
                cameraPermissionDeniedSheet
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(
                    onImage: { image in
                        showCamera = false
                        Task { await scan(image: image) }
                    },
                    onError: { message in
                        showCamera = false
                        errorMessage = message
                    }
                )
            }
        }
    }

    // MARK: - P1-B: Permission gate
    private func checkCameraPermissionAndPresent() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true }
                    else       { showPermissionSheet = true }
                }
            }
        case .denied, .restricted:
            showPermissionSheet = true
        @unknown default:
            showCamera = true
        }
    }

    @ViewBuilder
    private var cameraPermissionDeniedSheet: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.title2.weight(.semibold))
            Text("Camera access is needed to scan receipts. Please enable it in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Not Now") { showPermissionSheet = false }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .presentationDetents([.medium])
    }

    // MARK: - Scan helpers
    private func loadAndScan(item: PhotosPickerItem) async {
        isScanning = true; errorMessage = nil
        do {
            guard let data  = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load image."; isScanning = false; return
            }
            await scan(image: image)
        } catch {
            errorMessage = error.localizedDescription; isScanning = false
        }
    }

    private func scan(image: UIImage) async {
        isScanning = true; errorMessage = nil
        do {
            let result = try await ReceiptScannerService.shared.scan(image: image)
            await MainActor.run {
                isScanning = false
                if result.items.isEmpty { errorMessage = "No items found. Try a clearer photo." }
                else                    { scanResult = result }
            }
        } catch {
            await MainActor.run { isScanning = false; errorMessage = error.localizedDescription }
        }
    }
}

// P1-B: CameraPickerView guards against simulator / unavailable source type.
struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        // P1-B: Simulator / iPod guard — never crash on unavailable source type.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.async {
                self.onError("Camera not available on this device.")
            }
            return UIViewController()
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onError: (String) -> Void
        init(onImage: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void) {
            self.onImage = onImage; self.onError = onError
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
