import AVFoundation
import UIKit
import Vision
extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}

public class SwiftCunningDocumentScannerPlugin: NSObject, FlutterPlugin, AVCapturePhotoCaptureDelegate {
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
    
    let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
    
    let detectRectanglesRequest = VNDetectRectanglesRequest { (request, error) in
        guard let observations = request.results as? [VNRectangleObservation], let detectedRectangle = observations.first else {
            print("No rectangles detected.")
            self.resultChannel?(nil)
            return
        }

            if let overlayView = UIApplication.shared.keyWindow?.rootViewController?.view.subviews.first(where: { $0 is OverlayView }) as? OverlayView {
        overlayView.updateRectangle(detectedRectangle)
    }
        
        let ciImage = CIImage(cgImage: image.cgImage!)
        let croppedImage = self.cropImage(ciImage, rectangle: detectedRectangle)
        
        let tempDirPath = self.getDocumentsDirectory()
        let currentDateTime = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let formattedDate = df.string(from: currentDateTime)
        
        let url = tempDirPath.appendingPathComponent(formattedDate + "-0.png")
        
        if let pngData = croppedImage.pngData() {
            try? pngData.write(to: url)
        }
        
        self.resultChannel?([url.path])

        if let presentedVC = UIApplication.shared.keyWindow?.rootViewController {
            self.stopCaptureSession()
            self.previewLayer = nil
            self.captureSession = nil
            self.photoOutput = nil
        }
    }
    
    do {
        try requestHandler.perform([detectRectanglesRequest])
    } catch {
        print("Failed to perform rectangle detection: \(error.localizedDescription)")
        resultChannel?(nil)
    }
}





func cropImage(_ image: CIImage, rectangle: VNRectangleObservation) -> UIImage {
    let topLeft = rectangle.topLeft.scaled(to: image.extent.size)
    let topRight = rectangle.topRight.scaled(to: image.extent.size)
    let bottomLeft = rectangle.bottomLeft.scaled(to: image.extent.size)
    let bottomRight = rectangle.bottomRight.scaled(to: image.extent.size)
    
    let correctedImage = image.applyingFilter("CIPerspectiveCorrection", parameters: [
        "inputTopLeft": CIVector(cgPoint: topLeft),
        "inputTopRight": CIVector(cgPoint: topRight),
        "inputBottomLeft": CIVector(cgPoint: bottomLeft),
        "inputBottomRight": CIVector(cgPoint: bottomRight)
    ])
    
    let context = CIContext(options: nil)
    if let cgImage = context.createCGImage(correctedImage, from: correctedImage.extent) {
        return UIImage(cgImage: cgImage)
    } else {
        return UIImage(ciImage: correctedImage)
    }
}


    func addCaptureButton(in viewController: UIViewController) {
    let captureButton = UIButton(type: .system)
    captureButton.setTitle("APRILS PHOTO SCANNER", for: .normal)
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

