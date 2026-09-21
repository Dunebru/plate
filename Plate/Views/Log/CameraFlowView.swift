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
    var context: FoodAnalyzer.Context? = nil
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
                if camera.authorized { ReticleOverlay(mode: mode) }
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
                let analyzer = FoodAnalyzer(context: context)
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

/// The corner brackets over the camera.
///
/// They are not decoration. A photo taken from an angle, or with half the plate out of frame, is the
/// main reason a portion comes back wrong, and telling someone that in a sentence under the viewfinder
/// does not change how they hold the phone. A shape to fill does. The brackets are square for a plate
/// and wide for a nutrition panel, because those are the shapes of the two things being photographed.
private struct ReticleOverlay: View {
    var mode: CameraMode
    @State private var breathing = false

    private var aspect: CGFloat { mode == .food ? 1 : 1.6 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height / aspect) * 0.82
            let size = CGSize(width: side, height: side / aspect)
            ZStack {
                // A soft scrim outside the frame, so the eye goes to what is inside it.
                Color.black.opacity(0.28)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .frame(width: size.width, height: size.height)
                    }
                Brackets()
                    .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .scaleEffect(breathing ? 1.012 : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }
        .onAppear {
            // Slow enough to read as alive rather than as something demanding attention.
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// Four corners rather than a closed rectangle. A full box reads as a boundary you must not cross,
/// which makes people shrink the food inside it; corners read as an alignment guide.
private struct Brackets: Shape {
    var corner: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 18
        let c = min(corner, min(rect.width, rect.height) / 3)

        // Top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        // Top right
        path.move(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Bottom right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        // Bottom left
        path.move(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        return path
    }
}

private extension View {
    /// Punches a hole through a view, so the scrim dims everything except the frame.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
