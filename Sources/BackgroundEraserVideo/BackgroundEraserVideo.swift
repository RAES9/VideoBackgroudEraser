import Combine
import Vision
import MetalKit
import CoreImage.CIFilterBuiltins
import os.log
import AVFoundation

@available(iOS 15.0, *)
@available(macOS 12.0, *)
public class BackgroundEraserVideo {
    
    private static var privateShared : BackgroundEraserVideo?

    public class func shared() -> BackgroundEraserVideo {
        guard let uwShared = privateShared else {
            privateShared = BackgroundEraserVideo()
            return privateShared!
        }
        return uwShared
    }

    public var delegate: BackgroudEraserVideoDelegate! = nil
    private let requestHandler = VNSequenceRequestHandler()
    private var facePoseRequest: VNDetectFaceRectanglesRequest!
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var colors: AngleColors?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var adpater: AVAssetWriterInputPixelBufferAdaptor?
    private var totalDuration: Double!
    public var filename = ""
    private var time: Double = 0
    
    // MARK: - Delete Video Method
    
    public static func deleteBackground(url: URL, beforeProcess: (() -> ())? = nil) {
        privateShared?.facePoseRequest = VNDetectFaceRectanglesRequest { [weak privateShared] request, _ in
            guard let face = request.results?.first as? VNFaceObservation else { return }
            privateShared?.colors = AngleColors(roll: face.roll, pitch: face.pitch, yaw: face.yaw)
        }
        privateShared?.facePoseRequest.revision = VNDetectFaceRectanglesRequestRevision3
        privateShared?.segmentationRequest = VNGeneratePersonSegmentationRequest()
        privateShared?.segmentationRequest.qualityLevel = .balanced
        privateShared?.segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let beforeProcess = beforeProcess {
            beforeProcess()
        }
        let asset = AVAsset(url: url)
        privateShared?.totalDuration = asset.duration.seconds
        let reader = try! AVAssetReader(asset: asset)
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings:[String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
        reader.add(trackReaderOutput)
        reader.startReading()
        if privateShared?.filename == "" {
            privateShared?.filename = UUID().uuidString
        }
        let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(privateShared!.filename).mov")
        try? FileManager().removeItem(at: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(privateShared!.filename).mov").absoluteURL)
        let writer = try! AVAssetWriter(outputURL: videoPath, fileType: .mov)
        let settings = AVOutputSettingsAssistant(preset: .hevc1920x1080WithAlpha)?.videoSettings
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = CMTimeScale(bitPattern: 600)
        input.expectsMediaDataInRealTime = true
        input.transform = CGAffineTransform(rotationAngle: .pi/2)
        privateShared?.assetWriterInput = input
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: (privateShared?.assetWriterInput)!, sourcePixelBufferAttributes: nil)
        privateShared?.adpater = adapter
        privateShared?.assetWriter = writer
        if privateShared!.assetWriter!.canAdd(input) {
            privateShared!.assetWriter!.add(input)
        }
        privateShared!.assetWriter!.startWriting()
        privateShared!.assetWriter!.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        group.enter()
        let dispatchQueue = DispatchQueue(label: "QueueDeleteBackgorund", qos: .background)
        dispatchQueue.async(group: group, execute: {
            while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
                autoreleasepool {
                    privateShared?.processVideoFrame(pixelBuffer, sampleBuffer)
                }
            }
            group.leave()
        })
        group.notify(queue: DispatchQueue.main, execute: {
            guard privateShared?.assetWriterInput?.isReadyForMoreMediaData == true, privateShared?.assetWriter!.status != .failed else { return }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(privateShared!.filename).mov")
            privateShared?.assetWriterInput?.markAsFinished()
            privateShared?.assetWriter?.finishWriting { [weak privateShared] in
                privateShared?.assetWriter = nil
                privateShared?.assetWriterInput = nil
                DispatchQueue.main.async {
                    privateShared?.delegate.didFinishToProcesingVideo(url: url)
                }
            }
        })
    }
    
    // MARK: - Perform Requests

    private func processVideoFrame(_ framePixelBuffer: CVPixelBuffer, _ sampleBuffer: CMSampleBuffer) {
        try? requestHandler.perform([facePoseRequest, segmentationRequest],
                                    on: framePixelBuffer,
                                    orientation: .right)
        
        guard let maskPixelBuffer =
                segmentationRequest.results?.first?.pixelBuffer else { return }
        
        blend(original: framePixelBuffer, mask: maskPixelBuffer, sampleBuffer)
    }

    // MARK: - Process Results

    private func blend(original framePixelBuffer: CVPixelBuffer,
                       mask maskPixelBuffer: CVPixelBuffer, _ sampleBuffer: CMSampleBuffer) {
        guard colors != nil else { return }
        
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(.right)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
        
        let backgroundImage = CIImage(color: .clear).cropped(to: maskImage.extent)
        
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = originalImage
        blendFilter.backgroundImage = backgroundImage
        blendFilter.maskImage = maskImage
        
        let colorImage = blendFilter.outputImage?.oriented(.left)

        guard let staticImage = colorImage else {
            return
        }
        var pixelBuffer: CVPixelBuffer?
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        let width:Int = Int(staticImage.extent.size.width)
        let height:Int = Int(staticImage.extent.size.height)
        
        CVPixelBufferCreate(kCFAllocatorDefault,
                            width,
                            height,
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &pixelBuffer)
        
        let context = CIContext()
        
        context.render(staticImage, to: pixelBuffer!)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        delegate.procesingVideo(percentage: (timestamp / totalDuration) * 100)
        if assetWriterInput?.isReadyForMoreMediaData == true {
            let time = CMTime(seconds: timestamp, preferredTimescale: CMTimeScale(600))
            adpater?.append(pixelBuffer!, withPresentationTime: time)
        }
    }

    // MARK: - Angle Colors
    
    private struct AngleColors {
        
        let red: CGFloat
        let blue: CGFloat
        let green: CGFloat
        
        init(roll: NSNumber?, pitch: NSNumber?, yaw: NSNumber?) {
            red = AngleColors.convert(value: roll, with: -.pi, and: .pi)
            blue = AngleColors.convert(value: pitch, with: -.pi / 2, and: .pi / 2)
            green = AngleColors.convert(value: yaw, with: -.pi / 2, and: .pi / 2)
        }
        
        static func convert(value: NSNumber?, with minValue: CGFloat, and maxValue: CGFloat) -> CGFloat {
            guard let value = value else { return 0 }
            let maxValue = maxValue * 0.8
            let minValue = minValue + (maxValue * 0.2)
            let facePoseRange = maxValue - minValue
            
            guard facePoseRange != 0 else { return 0 }
            
            let colorRange: CGFloat = 1
            return (((CGFloat(truncating: value) - minValue) * colorRange) / facePoseRange)
        }
    }
}


