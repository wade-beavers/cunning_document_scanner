import AVFoundation
import Flutter
import UIKit
import Vision
import CoreImage.CIFilterBuiltins

@available(iOS 11.0, *)
public class SwiftCunningDocumentScannerPlugin: NSObject, FlutterPlugin, AVCapturePhotoCaptureDelegate {
    var resultChannel: FlutterResult?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var photoOutput: AVCapturePhotoOutput?
    var rootViewController: UIViewController?
    // var overlayView: UIView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cunning_document_scanner", binaryMessenger: registrar.messenger())
        let instance = SwiftCunningDocumentScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getPictures" {
            rootViewController = UIApplication.shared.keyWindow?.rootViewController
            self.resultChannel = result
            checkCameraPermissions { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.resultChannel?(FlutterError(code: "PERMISSION_DENIED",
                                                          message: "Camera permission denied",
                                                          details: nil))
                    }
                }
            }
        } else {
            result(FlutterMethodNotImplemented)
            return
        }
    }

    func checkCameraPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo

        guard let captureDevice = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: captureDevice),
              captureSession?.canAddInput(input) == true else {
            return
        }
        captureSession?.addInput(input)

        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession?.canAddOutput(photoOutput) == true {
            captureSession?.addOutput(photoOutput)
            setupLivePreview()
        }
    }

    func setupLivePreview() {
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        videoPreviewLayer?.videoGravity = .resizeAspectFill

        let scannerViewController = UIViewController()
        scannerViewController.view.layer.addSublayer(videoPreviewLayer!)

        // overlayView = UIView(frame: scannerViewController.view.bounds)
        // overlayView?.backgroundColor = UIColor(red: 220.0/255.0, green: 192.0/255.0, blue: 38.0/255.0, alpha: 0.5)
        // scannerViewController.view.addSubview(overlayView!)

        let shutterButton = UIButton(type: .system)
        shutterButton.setTitle("Take Photo", for: .normal)
        shutterButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        scannerViewController.view.addSubview(shutterButton)
        scannerViewController.view.bringSubviewToFront(shutterButton)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: scannerViewController.view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: scannerViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        videoPreviewLayer?.frame = scannerViewController.view.bounds
        captureSession?.startRunning()

        rootViewController?.present(scannerViewController, animated: true)
    }

    @objc func takePhoto() {
        guard let photoOutput = photoOutput else {
            return
        }
        let photoSettings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    public func photoOutput(_ output: AVCapturePhotoOutput,     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            resultChannel?(nil)
        } else if let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) {
            detectRectangles(image: image)
        } else {
            resultChannel?(nil)
        }

            // Remove overlay view
        // overlayView?.removeFromSuperview()
        // overlayView = nil

        captureSession?.stopRunning()
        rootViewController?.dismiss(animated: true)
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

    func perspectiveTransformedImage(from ciImage: CIImage, corners: [(CGFloat, CGFloat)]) -> CIImage? {
    guard corners.count == 4 else { return nil }

    let inputCorners = [
        CGPoint(x: corners[0].0 * ciImage.extent.width, y: corners[0].1 * ciImage.extent.height),
        CGPoint(x: corners[1].0 * ciImage.extent.width, y: corners[1].1 * ciImage.extent.height),
        CGPoint(x: corners[2].0 * ciImage.extent.width, y: corners[2].1 * ciImage.extent.height),
        CGPoint(x: corners[3].0 * ciImage.extent.width, y: corners[3].1 * ciImage.extent.height)
    ]

    let perspectiveCorrection = CIFilter.perspectiveCorrection()
    perspectiveCorrection.inputImage = ciImage
    perspectiveCorrection.topLeft = inputCorners[0]
    perspectiveCorrection.topRight = inputCorners[1]
    perspectiveCorrection.bottomRight = inputCorners[2]
    perspectiveCorrection.bottomLeft = inputCorners[3]

    return perspectiveCorrection.outputImage
}

// func drawTransparentRectangle(normalizedCorners: [(CGFloat, CGFloat)]) {
    // guard let overlayView = overlayView, let videoPreviewLayer = videoPreviewLayer else { return }

    // Remove any existing mask layer
    // overlayView.layer.sublayers?.forEach { if $0 is CAShapeLayer { $0.removeFromSuperlayer() } }

    // Create a new mask layer
    // let maskLayer = CAShapeLayer()
    // maskLayer.fillRule = .evenOdd
    // maskLayer.fillColor = UIColor(red: 220.0/255.0, green: 192.0/255.0, blue: 38.0/255.0, alpha: 0.5).cgColor

    // let overlayPath = UIBezierPath(rect: overlayView.bounds)

    // let rectanglePath = UIBezierPath()
    // rectanglePath.move(to: videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: normalizedCorners[0].0, y: normalizedCorners[0].1)))
    // rectanglePath.addLine(to: videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: normalizedCorners[1].0, y: normalizedCorners[1].1)))
    // rectanglePath.addLine(to: videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: normalizedCorners[2].0, y: normalizedCorners[2].1)))
    // rectanglePath.addLine(to: videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: normalizedCorners[3].0, y: normalizedCorners[3].1)))
    // rectanglePath.close()

    // overlayPath.append(rectanglePath)

    // maskLayer.path = overlayPath.cgPath

        // Add the mask layer to the overlay view
//     overlayView.layer.addSublayer(maskLayer)
// }




    func detectRectangles(image: UIImage) {
        guard let cgImage = image.cgImage else {
            resultChannel?(nil)
            return
        }

        let request = VNDetectRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNRectangleObservation] else {
                self?.resultChannel?(nil)
                return
            }

            if let bestRectangle = results.first {
                let normalizedCorners = [
                    (bestRectangle.topLeft.x, bestRectangle.topLeft.y),
                    (bestRectangle.topRight.x, bestRectangle.topRight.y),
                    (bestRectangle.bottomRight.x, bestRectangle.bottomRight.y),
                    (bestRectangle.bottomLeft.x, bestRectangle.bottomLeft.y)
                ]
                // self?.drawTransparentRectangle(normalizedCorners: normalizedCorners) // Add 'self?' here
                let ciImage = CIImage(image: image)!
                if let correctedCiImage = self?.perspectiveTransformedImage(from: ciImage, corners: normalizedCorners) {
                    let croppedUIImage = UIImage(ciImage: correctedCiImage)
                    self?.saveAndReturnImage(image: croppedUIImage)
                } else {
                    self?.resultChannel?(nil)
                }
            } else {
                self?.resultChannel?(nil)
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    

    func saveAndReturnImage(image: UIImage?) {
        guard let image = image else {
            resultChannel?(nil)
            return
        }

        let tempDirPath = self.getDocumentsDirectory()
        let currentDateTime = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let formattedDate = df.string(from: currentDateTime)
        let url = tempDirPath.appendingPathComponent("\(formattedDate).png")
        try? image.pngData()?.write(to: url)
        resultChannel?([url.path])
    }
}