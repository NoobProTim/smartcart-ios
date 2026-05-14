// MultiShotCaptureView.swift — SmartCart/Views/MultiShotCaptureView.swift
//
// Multi-shot receipt scanner. Replaces ReceiptScanView.
// User takes one or more photos of a receipt (useful for long receipts),
// then taps Process. Each image is OCR'd concurrently via ReceiptScannerService;
// results are merged by nameNormalised (highest confidence wins) and handed
// to ReceiptReviewView as [ParsedReceiptItem].
//
// Tap a thumbnail → selected state → Retake button appears → camera opens → replaces that slot.
// Tap elsewhere → deselects.

import SwiftUI
import AVFoundation

@MainActor
struct MultiShotCaptureView: View {

    @State private var capturedImages: [UIImage] = []
    @State private var selectedIndex: Int?        = nil
    @State private var retakeIndex: Int?          = nil
    @State private var isProcessing               = false
    @State private var showCamera                 = false
    @State private var showPermissionSheet        = false
    @State private var errorMessage: String?      = nil
    @State private var reviewItems: [ParsedReceiptItem]? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if capturedImages.isEmpty {
                        emptyPrompt
                    } else {
                        shotCountHeader
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if isProcessing {
                    ProgressView("Processing \(capturedImages.count) shot\(capturedImages.count == 1 ? "" : "s")…")
                        .padding(.bottom, 8)
                }

                if !capturedImages.isEmpty {
                    thumbnailStrip
                }

                actionBar
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(
                    onImage: { image in
                        showCamera = false
                        if let idx = retakeIndex {
                            capturedImages[idx] = image
                            retakeIndex = nil
                        } else {
                            capturedImages.append(image)
                        }
                        selectedIndex = nil
                        errorMessage  = nil
                    },
                    onError: { message in
                        showCamera   = false
                        retakeIndex  = nil
                        errorMessage = message
                    }
                )
            }
            .sheet(isPresented: $showPermissionSheet) {
                cameraPermissionDeniedSheet
            }
            .sheet(
                isPresented: Binding(
                    get: { reviewItems != nil },
                    set: { if !$0 { reviewItems = nil } }
                )
            ) {
                if let items = reviewItems {
                    ReceiptReviewView(
                        items: items,
                        isPresented: Binding(
                            get: { reviewItems != nil },
                            set: { if !$0 { reviewItems = nil } }
                        )
                    )
                }
            }
        }
        .onAppear { openCameraIfEmpty() }
    }

    // MARK: - Subviews

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Take photos of your receipt")
                .font(.headline)
            Text("Long receipts? Take multiple shots — order doesn't matter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var shotCountHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(capturedImages.count) shot\(capturedImages.count == 1 ? "" : "s") captured")
                .font(.headline)
            Text("Add more shots or tap Process.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(capturedImages.indices, id: \.self) { index in
                    thumbnailCell(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
    }

    private func thumbnailCell(index: Int) -> some View {
        let isSelected = selectedIndex == index
        return ZStack(alignment: .bottom) {
            Image(uiImage: capturedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(selectedIndex != nil && !isSelected ? 0.3 : 0))
                )

            if isSelected {
                Button {
                    retakeIndex   = index
                    selectedIndex = nil
                    checkCameraPermissionAndPresent()
                } label: {
                    Text("Retake")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 6)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedIndex = (selectedIndex == index) ? nil : index
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                selectedIndex = nil
                retakeIndex   = nil
                checkCameraPermissionAndPresent()
            } label: {
                Label("Add Shot", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)

            Button {
                processAllShots()
            } label: {
                if isProcessing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Process", systemImage: "doc.text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(capturedImages.isEmpty || isProcessing)
        }
        .padding()
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
            Text("Enable camera access in Settings to scan receipts.")
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

    // MARK: - Camera helpers

    private func openCameraIfEmpty() {
        if capturedImages.isEmpty { checkCameraPermissionAndPresent() }
    }

    private func checkCameraPermissionAndPresent() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.showCamera = true }
                    else       { self.showPermissionSheet = true }
                }
            }
        case .denied, .restricted:
            showPermissionSheet = true
        @unknown default:
            showCamera = true
        }
    }

    // MARK: - Processing

    private func processAllShots() {
        isProcessing  = true
        errorMessage  = nil
        selectedIndex = nil

        Task {
            var allItems: [ScannedLineItem] = []

            await withTaskGroup(of: [ScannedLineItem].self) { group in
                for image in capturedImages {
                    group.addTask {
                        (try? await ReceiptScannerService.shared.scan(image: image))?.items ?? []
                    }
                }
                for await items in group {
                    allItems.append(contentsOf: items)
                }
            }

            // Deduplicate: same nameNormalised → keep highest confidence
            var seen: [String: ScannedLineItem] = [:]
            for item in allItems {
                if let existing = seen[item.nameNormalised] {
                    if item.confidence > existing.confidence { seen[item.nameNormalised] = item }
                } else {
                    seen[item.nameNormalised] = item
                }
            }

            let parsed = seen.values.map { item in
                ParsedReceiptItem(
                    rawName:        item.nameRaw,
                    normalisedName: item.nameNormalised,
                    parsedPrice:    item.price,
                    confidence:     item.confidence >= 0.8 ? .high : .medium
                )
            }

            isProcessing = false
            if parsed.isEmpty {
                errorMessage = "No items found. Try clearer photos."
            } else {
                reviewItems = parsed
            }
        }
    }
}

// MARK: - CameraPickerView
// Moved here from the deleted ReceiptScanView.swift.
struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.async { self.onError("Camera not available on this device.") }
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
            self.onImage = onImage
            self.onError = onError
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
