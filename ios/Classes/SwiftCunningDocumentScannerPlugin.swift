import AVFoundation
import UIKit
import Vision

public class SwiftCunningDocumentScannerPlugin: NSObject, FlutterPlugin, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var resultChannel: FlutterResult?
    var captureSession: AVCaptureSession?
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cunning_document_scanner", binaryMessenger: registrar.messenger())
        let instance = SwiftCunningDocumentScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getPictures" {
            let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
            self.resultChannel = result
            startCaptureSession(in: presentedVC!)
        } else {
            result(FlutterMethodNotImplemented)
            return
        }
    }
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error setting up capture device.")
            return
        }
        
        if (captureSession?.canAddInput(input) == true) {
            captureSession?.addInput(input)
        }
        
        photoOutput = AVCapturePhotoOutput()
        if (captureSession?.canAddOutput(photoOutput!) == true) {
            captureSession?.addOutput(photoOutput!)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if (captureSession?.canAddOutput(videoOutput) == true) {
            captureSession?.addOutput(videoOutput)
        }
    }
    
    func startCaptureSession(in viewController: UIViewController) {
        setupCaptureSession()
        captureSession?.startRunning()

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.connection?.videoOrientation = .portrait
        previewLayer?.frame = viewController.view.bounds
        viewController.view.layer.insertSublayer(previewLayer!, at: 0)

        let overlayView = OverlayView(frame: viewController.view.bounds, previewLayer: previewLayer!)
        viewController.view.addSubview(overlayView)

        addCaptureButton(in: viewController)
    }
    
    func stopCaptureSession() {
        captureSession?.stopRunning()
        previewLayer?.removeFromSuperlayer()
    }
    
public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
        resultChannel?(nil)
        return
    }

    let tempDirPath = self.getDocumentsDirectory()
    let currentDateTime = Date()
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let formattedDate = df.string(from: currentDateTime)

    let url = tempDirPath.appendingPathComponent(formattedDate + "-0.png")
    try? image.pngData()?.write(to: url)

    resultChannel?([url.path])

    if let presentedVC = UIApplication.shared.keyWindow?.rootViewController {
        stopCaptureSession()
        previewLayer = nil
        captureSession = nil
        photoOutput = nil
        presentedVC.view.subviews.forEach { view in
            if view is OverlayView || view is UIButton {
                view.removeFromSuperview()
            }
        }
    }
}

    func addCaptureButton(in viewController: UIViewController) {
        let captureButton = UIButton(type: .system)
        captureButton.setTitle("Capture", for: .normal)
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    @objc func capturePhoto() {
        guard let photoOutput = self.photoOutput else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        let detectRectanglesRequest = VNDetectRectanglesRequest { (request, error) in
            guard let observations = request.results as? [VNRectangleObservation], let detectedRectangle = observations.first else {
                return
            }

            DispatchQueue.main.async {
                if let overlayView = UIApplication.shared.keyWindow?.rootViewController?.view.subviews.first(where: { $0 is OverlayView }) as? OverlayView {
                    overlayView.updateRectangle(detectedRectangle)
                }
            }
        }

        do {
            try imageRequestHandler.perform([detectRectanglesRequest])
        } catch {
            print("Failed to perform rectangle detection: \(error.localizedDescription)")
        }
    }
}

class OverlayView: UIView {
    var rectangle: VNRectangleObservation?
    var previewLayer: AVCaptureVideoPreviewLayer?

    init(frame: CGRect, previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let rectangle = rectangle, let previewLayer = previewLayer else { return }

        context.clear(rect)

        let fillColor = UIColor(red: 63 / 255, green: 181 / 255, blue: 86 / 255, alpha: 0.5)
        context.setFillColor(fillColor.cgColor)

        let topLeft = previewLayer.layerPointConverted(fromCaptureDevicePoint: rectangle.topLeft)
        let topRight = previewLayer.layerPointConverted(fromCaptureDevicePoint: rectangle.topRight)
        let bottomLeft = previewLayer.layerPointConverted(fromCaptureDevicePoint: rectangle.bottomLeft)
        let bottomRight = previewLayer.layerPointConverted(fromCaptureDevicePoint: rectangle.bottomRight)

        context.beginPath()
        context.move(to: topLeft)
        context.addLine(to: topRight)
        context.addLine(to: bottomRight)
        context.addLine(to: bottomLeft)
        context.closePath()
        context.fillPath()
    }

    func updateRectangle(_ rectangle: VNRectangleObservation) {
        self.rectangle = rectangle
        setNeedsDisplay()
    }
}


