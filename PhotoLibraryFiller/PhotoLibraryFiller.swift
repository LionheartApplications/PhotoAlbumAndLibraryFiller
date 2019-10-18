/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Controller class responsible for generating, saving, and adding photos to the photo library.
*/

import UIKit
import CoreLocation
import ImageIO
import Photos
import MobileCoreServices

public protocol PhotoLibraryFillerDelegate : class {
    func photoLibraryFillerDidUpdate(_ photoLibraryFiller: PhotoLibraryFiller)
    func photoLibraryFiller(_ photoLibraryFiller: PhotoLibraryFiller, didGenerate image: UIImage)
    func photoLibraryFiller(_ photoLibraryFiller: PhotoLibraryFiller, didEncounterErrorWith message: String)
}

public class PhotoLibraryFiller {
    
    public var photosToAdd = 100_000 {
        didSet {
            notifyDelegateOfDidUpdate()
        }
    }
    public var active = false {
        didSet {
            startAddingPhotosIfNeeded()
            notifyDelegateOfDidUpdate()
        }
    }
    public weak var delegate: PhotoLibraryFillerDelegate?
    
    private var isAddingPhotos = false
    private let workQueue: DispatchQueue
    private let photoLibrarySemaphore = DispatchSemaphore(value: 1)
    
    private let maxBatchSize = 10
    private let graphicsRenderers: [UIGraphicsImageRenderer]
    private let formatter: DateFormatter
    
    private var lastHue: CGFloat
    private var lastCoordinate: CLLocationCoordinate2D
    private var lastDate: Date
    
    public init() {
        workQueue = DispatchQueue(label: "PhotoLibraryFiller-WorkQueue",
                                  qos: .userInitiated,
                                  attributes: DispatchQueue.Attributes(rawValue: 0),
                                  autoreleaseFrequency: .workItem,
                                  target: nil)
        
        let landscapeImageSize = CGSize(width: 1024, height: 768)
        let portraitImageSize = CGSize(width: 768, height: 1024)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var graphicsRenderers: [UIGraphicsImageRenderer] = []
        for index in 0..<maxBatchSize {
            let imageSize = index % 2 == 0 ? landscapeImageSize : portraitImageSize
            graphicsRenderers.append(UIGraphicsImageRenderer(size: imageSize, format: format))
        }
        self.graphicsRenderers = graphicsRenderers
        
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        
        lastCoordinate = randomCoordinate()
        lastDate = randomDate()
        lastHue = 0
    }
    
    private func startAddingPhotosIfNeeded() {
        if active && !isAddingPhotos {
            isAddingPhotos = true
            checkAuthorization { success in
                if success {
                    self.addPhotos()
                } else {
                    self.isAddingPhotos = false
                    self.active = false
                }
            }
        }
    }
    
    private func checkAuthorization(completion: @escaping (_ success: Bool) -> Void) {
        let authorizationStatus = PHPhotoLibrary.authorizationStatus()
        
        switch authorizationStatus {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                let success = status == .authorized
                DispatchQueue.main.async {
                    completion(success)
                }
            }
            
        case .restricted, .denied:
            let errorMessage = "Not authorized to add photos to the photo library"
            print(errorMessage)
            delegate?.photoLibraryFiller(self, didEncounterErrorWith: errorMessage)
            completion(false)
        
        @unknown default:
            fatalError()
        }
    }
    
    private func addPhotos() {
        let batchSize = min(photosToAdd, maxBatchSize)
        if batchSize <= 0 || !active {
            isAddingPhotos = false
            active = false
            return
        }
        
        workQueue.async {
            let fileURLs = self.generateImagesAndWriteToDisk(batchSize: batchSize)
            self.createPhotoLibraryAssets(with: fileURLs)
            
            DispatchQueue.main.async {
                self.addPhotos()
            }
        }
    }
    
    private func generateImagesAndWriteToDisk(batchSize: Int) -> [URL] {
        let locations = (0..<batchSize).map { _ in return nextLocation() }
        let colors = (0..<batchSize).map { _ in return nextColor() }
        let graphicsRenderers = self.graphicsRenderers
        let formatter = self.formatter

        var writtenURLs = [URL]()
        
        DispatchQueue.concurrentPerform(iterations: batchSize) { index in
            let renderer = graphicsRenderers[index]
            let color = colors[index]
            let location = locations[index]
            let date = location.timestamp
            
            let image = randomImage(renderer: renderer, backgroundColor: color)
            self.notifyDelegateOfGeneratedImage(image: image)
            
            let jpegData = image.jpegData(compressionQuality: 0)!
            let filename = "\(NSTemporaryDirectory())photolibraryfiller_\(NSUUID().uuidString).jpg"
            let fileURL = URL(fileURLWithPath: filename, isDirectory: false)
            
            var metadata = [String: Any]()
            
            metadata[String(kCGImagePropertyExifDictionary)] = [String(kCGImagePropertyExifDateTimeOriginal): formatter.string(from: date)]
            
            var gpsDictionary = [String: Any]()
            gpsDictionary[String(kCGImagePropertyGPSLatitude)] = fabs(location.coordinate.latitude)
            gpsDictionary[String(kCGImagePropertyGPSLatitudeRef)] = location.coordinate.latitude >= 0 ? "N" : "S"
            gpsDictionary[String(kCGImagePropertyGPSLongitude)] = fabs(location.coordinate.longitude)
            gpsDictionary[String(kCGImagePropertyGPSLongitudeRef)] = location.coordinate.longitude >= 0 ? "E" : "W"
            metadata[String(kCGImagePropertyGPSDictionary)] = gpsDictionary
            
            if writeToDisk(jpegData: jpegData, to: fileURL, with: metadata) {
                DispatchQueue.main.sync {
                    writtenURLs.append(fileURL)
                    if self.active {
                        photosToAdd -= 1
                    }
                }
            }
        }
        
        return writtenURLs
    }
    
    private func createPhotoLibraryAssets(with imageFileURLs: [URL]) {
        photoLibrarySemaphore.wait() // Wait for any ongoing photo library
        
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            let ids = imageFileURLs.compactMap { (url) -> PHObjectPlaceholder? in
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: url, options: options)
                return creationRequest.placeholderForCreatedAsset
            }
            
            
            let creationRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: UUID().uuidString)
            creationRequest.addAssets(ids as NSArray)
            
        }) { (success, error) in
            if !success {
                print("Error saving asset to library:\(String(describing: error?.localizedDescription))")
            }
            self.photoLibrarySemaphore.signal()
        }
    }
    
    private func writeToDisk(jpegData: Data, to fileURL: URL, with metadata: [String: Any]) -> Bool {
        var success = false
        
        jpegData.withUnsafeBytes {
            let dataPointer = $0.bindMemory(to: UInt8.self)
            guard let cfData = CFDataCreate(kCFAllocatorDefault, dataPointer.baseAddress, jpegData.count) else { return }
            guard let source = CGImageSourceCreateWithData(cfData, nil) else { return }
            guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, kUTTypeJPEG, 1, nil) else { return }
        
            CGImageDestinationAddImageFromSource(destination, source, 0, metadata as NSDictionary)
            success = CGImageDestinationFinalize(destination)
        
            if !success {
                print("Error writing jpeg data to disk")
            }
            
            return
        }

        return success
    }
    
    private func nextLocation() -> CLLocation {
        let shouldMoveToNewLocation = randomDouble() > 0.95
        if shouldMoveToNewLocation {
            lastCoordinate = randomCoordinate()
            lastDate = randomDate()
        }
        
        let date = lastDate.addingTimeInterval(randomDouble() * 10)
        
        let location = CLLocation(coordinate: lastCoordinate,
                                  altitude: 0,
                                  horizontalAccuracy: 100,
                                  verticalAccuracy: 100,
                                  timestamp: date)
        return location
    }
    
    private func nextColor() -> UIColor {
        let nextHue = fmod(lastHue + 0.03, 1.0)
        let nextColor = UIColor(hue: nextHue, saturation: 1, brightness: 1, alpha: 1)
        lastHue = nextHue
        return nextColor
    }
    
    private func notifyDelegateOfDidUpdate() {
        delegate?.photoLibraryFillerDidUpdate(self)
    }
    
    private func notifyDelegateOfGeneratedImage(image: UIImage) {
        DispatchQueue.main.async {
            self.delegate?.photoLibraryFiller(self, didGenerate: image)
        }
    }
}

private func randomImage(renderer: UIGraphicsImageRenderer, backgroundColor: UIColor) -> UIImage {
    let image = renderer.image { context in
        let bounds = context.format.bounds
        let shortSide = min(bounds.size.width, bounds.size.height)
        
        backgroundColor.setFill()
        context.fill(bounds)
        
        let text = String(format: "%.3f.%03u", Date.timeIntervalSinceReferenceDate, arc4random_uniform(1000))
        let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: shortSide * 0.1),
                          NSAttributedString.Key.foregroundColor: UIColor.white]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        
        let labelSize = attributedString.size()
        let labelOrigin = CGPoint(x: (bounds.size.width - labelSize.width) / 2.0,
                                  y: (bounds.size.height - labelSize.height) / 2.0)
        let labelRect = CGRect(origin: labelOrigin, size: labelSize)
        attributedString.draw(in: labelRect)
    }
    return image
}

private func randomCoordinate() -> CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: 55.825973 + randomDouble() * 9.050965,
                                  longitude: 11.769221 + randomDouble() * 5.668945)
}

private func randomDate() -> Date {
    return Date(timeIntervalSince1970: 315532800 + randomDouble() * 599616000)
}

private func randomDouble() -> Double {
    return Double(Double(arc4random()) / Double(UINT32_MAX))
}
