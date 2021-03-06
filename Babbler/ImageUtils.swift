import Cocoa
import Carbon

@objc class ImageUtils: NSObject {

    static private var images: [String: NSImage] = [:]
    
    static private func generateSecurityInputLangImage(_ image: NSImage) -> NSImage {
        
        // Add grayscale filter
        let currentCIImage = CIImage(data: image.tiffRepresentation!)
        let filter = CIFilter(name: "CIColorMonochrome")
        filter?.setValue(currentCIImage, forKey: "inputImage")
        filter?.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
        filter?.setValue(1.0, forKey: "inputIntensity")
        let outputImage = filter?.outputImage
        let context = CIContext()
        let cgimg = context.createCGImage(outputImage!, from: outputImage!.extent)
        
//        let caLayer = CALayer();
//
//        caLayer.addSublayer(<#T##layer: CALayer##CALayer#>)
        // https://riptutorial.com/ios/example/16243/how-to-add-a-uiimage-to-a-calayer
        // https://stackoverflow.com/questions/41386423/get-image-from-calayer-or-nsview-swift-3
        
        return NSImage(cgImage: cgimg!, size: NSMakeSize(16.0, 16.0))
    }
    
    static private func generateLangImage(_ inputSource: TISInputSource, _ isSecurityInput: Bool) -> NSImage {
        let image = NSImage(iconRef: inputSource.iconRef!);
        image.size = NSMakeSize(16.0, 16.0)
        return isSecurityInput ? generateSecurityInputLangImage(image) : image;
    }
    
    static func getLangImage(_ inputSource: TISInputSource, _ isSecurityInput: Bool) -> NSImage {
        let key = "\(inputSource.id) \(isSecurityInput)"
        if (images[key] != nil) {
            return images[key]!
        }
        images[key] = generateLangImage(inputSource, isSecurityInput);
        return images[key]!
    }
}
