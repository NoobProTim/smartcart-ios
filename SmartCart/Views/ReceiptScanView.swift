// ReceiptScanView.swift — SmartCart/Views/ReceiptScanView.swift
//
// Camera → OCR → review scanned items → confirm import to database.

import SwiftUI
import PhotosUI

struct ReceiptScanView: View {

    @State private var showCamera      = false
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var scanResult: ReceiptScanResult? = nil
    @State private var isScanning      = false
    @State private var errorMessage: String? = nil

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

                if isScanning {
                    ProgressView("Scanning…")
                }

                if let err = errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)

                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images
                    ) {
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView { image in
                    showCamera = false
                    Task { await scan(image: image) }
                }
            }
            .sheet(item: $scanResult) { result in
                ReceiptReviewView(result: result) {
                    scanResult = nil
                }
            }
        }
    }

    // MARK: - Scan helpers

    private func loadAndScan(item: PhotosPickerItem) async {
        isScanning = true
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load image."
                isScanning = false
                return
            }
            await scan(image: image)
        } catch {
            errorMessage = error.localizedDescription
            isScanning = false
        }
    }

    private func scan(image: UIImage) async {
        isScanning = true
        errorMessage = nil
        do {
            let result = try await ReceiptScannerService.shared.scan(image: image)
            await MainActor.run {
                isScanning = false
                if result.items.isEmpty {
                    errorMessage = "No items found. Try a clearer photo."
                } else {
                    scanResult = result
                }
            }
        } catch {
            await MainActor.run {
                isScanning = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Wraps UIImagePickerController for camera access.
struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
        }
    }
}
