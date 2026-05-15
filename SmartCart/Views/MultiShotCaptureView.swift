// MultiShotCaptureView.swift — SmartCart/Views/MultiShotCaptureView.swift
//
// Full-screen live-viewfinder receipt scanner.
// The camera stays open between shots — tap the shutter button for each
// section of a long receipt, then tap Process when done.
//
// Store is auto-detected from the OCR raw lines after processing —
// no manual picker needed.
//
// Thumbnail strip: tap a thumbnail to select it, tap the × to delete it.

import SwiftUI
import AVFoundation
import Combine

// MARK: - CameraSessionManager

@MainActor
final class CameraSessionManager: ObservableObject {

    let session        = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var activeDelegate: PhotoCaptureDelegate?

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input  = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func start() { Task.detached(priority: .userInitiated) { [s = session] in s.startRunning()  } }
    func stop()  { Task.detached                           { [s = session] in s.stopRunning()   } }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { cont in
            let del = PhotoCaptureDelegate { img in cont.resume(returning: img) }
            activeDelegate = del
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: del)
        }
    }
}

// MARK: - PhotoCaptureDelegate (non-isolated helper)

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        completion(image)
    }
}

// MARK: - LiveCameraPreview

struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            previewLayer.session      = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}

// MARK: - MultiShotCaptureView

@MainActor
struct MultiShotCaptureView: View {

    @StateObject private var camera = CameraSessionManager()

    @State private var images: [UIImage]              = []
    @State private var selectedIndex: Int?            = nil
    @State private var isCapturing                    = false
    @State private var isProcessing                   = false
    @State private var reviewItems: [ParsedReceiptItem]? = nil
    @State private var detectedStore: Store?          = nil
    @State private var stores: [Store]                = []
    @State private var errorMessage: String?          = nil
    @State private var hapticTrigger                  = 0
    @State private var showPermissionSheet            = false

    @Environment(\.dismiss) private var dismiss

    private var hasCameraHardware: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var body: some View {
        ZStack {
            // Background: live preview or simulator placeholder
            if hasCameraHardware {
                LiveCameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Camera unavailable")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            // Controls overlay
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)
                Spacer()
                if let err = errorMessage {
                    errorBadge(err)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomControls
            }
        }
        .ignoresSafeArea()
        .onAppear {
            stores = DatabaseManager.shared.fetchSelectedStores()
            requestPermissionAndStart()
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showPermissionSheet) {
            permissionSheet
        }
        .sheet(
            isPresented: Binding(get: { reviewItems != nil }, set: { if !$0 { reviewItems = nil } })
        ) {
            if let items = reviewItems {
                ReceiptReviewView(
                    items: items,
                    storeID: detectedStore?.id,
                    storeName: detectedStore?.name,
                    isPresented: Binding(
                        get: { reviewItems != nil },
                        set: { if !$0 { reviewItems = nil; dismiss() } }
                    )
                )
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Auto-detected store badge
            HStack(spacing: 5) {
                Image(systemName: "storefront")
                    .font(.system(size: 12, weight: .semibold))
                Text(detectedStore?.name ?? (isProcessing ? "Detecting…" : "Store auto-detects"))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Process button
            Button { processAllShots() } label: {
                Group {
                    if isProcessing {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Text("Process")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 80, height: 38)
                .background(
                    images.isEmpty
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color.accentColor),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .disabled(images.isEmpty || isProcessing)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Thumbnail strip
            if !images.isEmpty {
                thumbnailStrip
                    .padding(.bottom, 20)
            }

            // Shutter row
            HStack(alignment: .center) {
                // Shot count
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(images.count)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(images.count == 1 ? "shot" : "shots")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Shutter
                Button { captureShot() } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white.opacity(0.45), lineWidth: 4)
                            .frame(width: 82, height: 82)
                        Circle()
                            .fill(.white)
                            .frame(width: 68, height: 68)
                        if isCapturing {
                            ProgressView().tint(Color.accentColor).scaleEffect(1.1)
                        }
                    }
                }
                .disabled(isCapturing || isProcessing)
                .scaleEffect(isCapturing ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: isCapturing)

                // Hint
                Text("Tap for each\nsection")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 36)
            .padding(.top, 16)
            .padding(.bottom, 48)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    // MARK: Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(images.indices, id: \.self) { idx in
                    thumbnailCell(index: idx)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 108)
    }

    private func thumbnailCell(index: Int) -> some View {
        let selected = selectedIndex == index
        return ZStack(alignment: .topTrailing) {
            Image(uiImage: images[index])
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            selected ? Color.accentColor : Color.white.opacity(0.25),
                            lineWidth: selected ? 2.5 : 1
                        )
                )
                .overlay(alignment: .bottom) {
                    Text("#\(index + 1)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 5)
                }

            // Delete badge — visible only when selected
            if selected {
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        images.remove(at: index)
                        selectedIndex = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .shadow(radius: 2)
                }
                .offset(x: 8, y: -8)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .onTapGesture {
            withAnimation(.spring(duration: 0.2, bounce: 0.15)) {
                selectedIndex = (selectedIndex == index) ? nil : index
            }
        }
    }

    // MARK: Error badge

    private func errorBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Permission sheet

    private var permissionSheet: some View {
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

    // MARK: - Actions

    private func requestPermissionAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            camera.configure()
            camera.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.camera.configure(); self.camera.start() }
                    else       { self.showPermissionSheet = true }
                }
            }
        case .denied, .restricted:
            showPermissionSheet = true
        @unknown default:
            camera.configure()
            camera.start()
        }
    }

    private func captureShot() {
        isCapturing  = true
        errorMessage = nil
        selectedIndex = nil
        Task {
            if let img = await camera.capturePhoto() {
                images.append(img)
                hapticTrigger += 1
            }
            isCapturing = false
        }
    }

    private func processAllShots() {
        guard !images.isEmpty else { dismiss(); return }
        isProcessing  = true
        errorMessage  = nil
        selectedIndex = nil

        Task {
            typealias Chunk = (items: [ScannedLineItem], rawLines: [String])
            var allItems: [ScannedLineItem] = []
            var allRawLines: [String]       = []

            await withTaskGroup(of: Chunk.self) { group in
                for image in images {
                    group.addTask {
                        guard let r = try? await ReceiptScannerService.shared.scan(image: image) else {
                            return ([], [])
                        }
                        return (r.items, r.rawLines)
                    }
                }
                for await chunk in group {
                    allItems.append(contentsOf: chunk.items)
                    allRawLines.append(contentsOf: chunk.rawLines)
                }
            }

            // Auto-detect store from the first 20 OCR lines
            if detectedStore == nil {
                let haystack = allRawLines.prefix(20).joined(separator: " ").lowercased()
                detectedStore = stores.first { haystack.contains($0.name.lowercased()) }
            }

            // Deduplicate: keep highest-confidence scan for each normalised name
            var seen: [String: ScannedLineItem] = [:]
            for item in allItems {
                if let existing = seen[item.nameNormalised] {
                    if item.confidence > existing.confidence { seen[item.nameNormalised] = item }
                } else {
                    seen[item.nameNormalised] = item
                }
            }

            let parsed = seen.values
                .sorted { $0.nameNormalised < $1.nameNormalised }
                .map {
                    ParsedReceiptItem(
                        rawName:        $0.nameRaw,
                        normalisedName: $0.nameNormalised,
                        parsedPrice:    $0.price,
                        confidence:     $0.confidence >= 0.8 ? .high : .medium
                    )
                }

            isProcessing = false
            if parsed.isEmpty {
                withAnimation { errorMessage = "No items found. Try clearer photos." }
            } else {
                reviewItems = parsed
            }
        }
    }
}
