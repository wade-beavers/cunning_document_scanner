import Flutter
import UIKit
import WeScan

extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
            let g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
            let b = CGFloat(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            self.init(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        }
    }
}

public class SwiftCunningDocumentScannerPlugin: UIViewController, FlutterPlugin,  ImageScannerControllerDelegate {
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
            self.presentingController?.view.backgroundColor = UIColor(hex: "#D2CBC3")
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
