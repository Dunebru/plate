import SwiftUI
import AVFoundation
import PhotosUI

enum CameraMode: Hashable {
    case food, label
    var title: String { self == .food ? "Scan food" : "Food label" }
    var hint: String { self == .food ? "Get the whole plate in frame, from above" : "Fill the frame with the nutrition facts panel" }
}

/// Camera preview with shutter and library picker, then the analyzing state.
struct CameraFlowView: View {
    var mode: CameraMode
    var onResult: (AnalyzedMeal, UIImage?) -> Void
    @StateObject private var camera = CameraController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var captured: UIImage?
    @State private var hint = ""
    @State private var analyzing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = captured {
                review(image)
            } else {
                live
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    captured = img
                }
            }
        }
        .alert("Could not analyze", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private var live: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if !camera.authorized {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("Camera access is off").font(.headline)
                        Text("Allow it in Settings, or pick a photo from your library.").font(.footnote)
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
            .padding(12)
            Text(mode.hint).font(.footnote).foregroundStyle(.white.opacity(0.7))
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.white).frame(width: 60, height: 60)
                }
                Spacer()
                Button {
                    camera.capture { img in captured = img }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64)
                    }
                }
                .disabled(!camera.authorized)
                Spacer()
                Color.clear.frame(width: 60, height: 60)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
    }

    private func review(_ image: UIImage) -> some View {
        VStack(spacing: 14) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(12)
                .overlay {
                    if analyzing {
                        VStack(spacing: 12) {
                            ProgressView().tint(.white).scaleEffect(1.4)
                            Text(mode == .food ? "Estimating portions" : "Reading the label").foregroundStyle(.white).font(.headline)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            if mode == .food {
                TextField("Anything the photo can't show? (\"cooked in butter\", \"half eaten\")", text: $hint, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .disabled(analyzing)
            }
            HStack(spacing: 12) {
                Button("Retake") { captured = nil; pickerItem = nil }
                    .buttonStyle(.bordered).tint(.white)
                    .disabled(analyzing)
                Button { analyze(image) } label: {
                    Text("Analyze").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(analyzing)
            }
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    private func analyze(_ image: UIImage) {
        analyzing = true
        Task {
            do {
                let analyzer = FoodAnalyzer()
                let meal = mode == .food ? try await analyzer.analyzePhoto(image, hint: hint) : try await analyzer.analyzeLabel(image)
                analyzing = false
                onResult(meal, image)
            } catch {
                analyzing = false
                self.error = error.localizedDescription
            }
        }
    }
}

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.dunebru.plate.camera")
    private var configured = false
    private var completion: ((UIImage) -> Void)?
    @Published var authorized = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { self.authorized = granted }
            guard granted else { return }
            self.queue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.maxPhotoQualityPrioritization = .balanced
        }
        session.commitConfiguration()
        configured = true
    }

    func capture(_ completion: @escaping (UIImage) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.completion?(image) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
