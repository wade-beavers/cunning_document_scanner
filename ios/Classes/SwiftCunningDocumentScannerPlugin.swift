import Flutter
import UIKit
import WeScan

public class SwiftCunningDocumentScannerPlugin: NSObject, FlutterPlugin, ImageScannerControllerDelegate {
    var resultChannel: FlutterResult?
    var presentingController: ImageScannerController?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cunning_document_scanner", binaryMessenger: registrar.messenger())
        let instance = SwiftCunningDocumentScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getPictures" {
            let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
            self.resultChannel = result
            self.presentingController = ImageScannerController()
            self.presentingController?.imageScannerDelegate = self
            presentedVC?.present(self.presentingController!, animated: true)
        } else {
            result(FlutterMethodNotImplemented)
            return
        }
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

   public func imageScannerController(_ scanner: ImageScannerController, didFinishScanningWithResults results: ImageScannerResults) {
    let tempDirPath = self.getDocumentsDirectory()
    let currentDateTime = Date()
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let formattedDate = df.string(from: currentDateTime)

    guard let imageData = results.croppedScan.image.jpegData(compressionQuality: 1.0) else {
        resultChannel?(nil)
        scanner.dismiss(animated: true)
        return
    }

    let url = tempDirPath.appendingPathComponent("\(formattedDate).jpg")
    try? imageData.write(to: url)
    resultChannel?([url.path])
    scanner.dismiss(animated: true)
}


    public func imageScannerControllerDidCancel(_ scanner: ImageScannerController) {
        resultChannel?(nil)
        scanner.dismiss(animated: true)
    }

    public func imageScannerController(_ scanner: ImageScannerController, didFailWithError error: Error) {
        resultChannel?(nil)
        scanner.dismiss(animated: true)
    }
}
