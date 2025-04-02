import Foundation
import AVFoundation
import CoreImage
import Network

let asciiChars = ["@", "#", "8", "&", "o", ":", "*", ".", " "]  // Darker → Lighter
var asciiWidth = 80  // Adjustable via UDP
var asciiHeight = 40

class ASCIIWebcam: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let context = CIContext()

    override init() {
        super.init()
        setupCamera()
        setupUDPListener()
    }

    func setupCamera() {
        session.sessionPreset = .low
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Error: Could not access webcam.")
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        session.addInput(input)
        session.addOutput(output)
        
        session.startRunning()
    }

    func setupUDPListener() {
        let listenerQueue = DispatchQueue(label: "UDPListener")
        let listener = try? NWListener(using: .udp, on: 9000)  // Listen on port 9999

        listener?.newConnectionHandler = { connection in
            connection.start(queue: listenerQueue)
            connection.receiveMessage { (data, _, _, error) in
                if let data = data, let message = String(data: data, encoding: .utf8) {
                    self.handleUDPMessage(message)
                }
                if error == nil {
                    //connection.receiveMessage(completion: self.handleUDPMessage(_:))
                    print(error)
                }
            }
        }

        listener?.start(queue: listenerQueue)
        print("Listening for UDP messages on port 9999...")
    }

    func handleUDPMessage(_ message: String) {
        let parts = message.split(separator: ", ")
        if parts.count == 2, let newWidth = Int(parts[0]), let newHeight = Int(parts[1]) {
            asciiWidth = max(20, min(newWidth, 160))   // Clamp values for safety
            asciiHeight = max(10, min(newHeight, 80))
            print("Updated ASCII resolution: \(asciiWidth)x\(asciiHeight)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let edgesFilter = CIFilter(name: "CIEdges")!
        edgesFilter.setValue(ciImage, forKey: kCIInputImageKey)

        if let outputImage = edgesFilter.outputImage {
            print("\u{001B}[H") // Move cursor to top (clears previous output)
            print(asciiArt(from: outputImage, width: asciiWidth, height: asciiHeight))
        }
    }

    func asciiArt(from ciImage: CIImage, width: Int, height: Int) -> String {
        let resized = ciImage.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / ciImage.extent.width, y: CGFloat(height) / ciImage.extent.height))
        let grayFilter = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: resized, kCIInputSaturationKey: 0])
        
        guard let grayImage = grayFilter?.outputImage,
              let cgImage = context.createCGImage(grayImage, from: grayImage.extent) else { return "" }

        let bitmap = CFDataGetBytePtr(cgImage.dataProvider!.data)!
        let bytesPerPixel = 4
        var asciiStr = ""

        for y in stride(from: 0, to: height, by: 1) {
            for x in stride(from: 0, to: width, by: 1) {
                let offset = (y * cgImage.width + x) * bytesPerPixel
                let brightness = (0.299 * Double(bitmap[offset]) +
                                  0.587 * Double(bitmap[offset + 1]) +
                                  0.114 * Double(bitmap[offset + 2])) / 255.0
                let index = Int(brightness * Double(asciiChars.count - 1))
                asciiStr.append(asciiChars[index])
            }
            asciiStr.append("\n")
        }
        return asciiStr
    }
}

// Start ASCII webcam with UDP listening
let processor = ASCIIWebcam()
RunLoop.main.run()

