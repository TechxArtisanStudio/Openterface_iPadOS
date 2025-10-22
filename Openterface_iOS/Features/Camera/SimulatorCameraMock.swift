//
//  SimulatorCameraMock.swift
//  Openterface_iOS
//
//  Created for Simulator Testing
//

import Foundation
import AVFoundation
import UIKit
import Combine

#if targetEnvironment(simulator)

/// Mock camera manager for simulator that provides a test video feed
final class SimulatorCameraMock: NSObject {
    // MARK: - Published Properties
    @Published var isActive = false
    
    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemVideoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var sampleBufferDelegate: ((CMSampleBuffer) -> Void)?
    
    // Test video properties
    private var testVideoURL: URL?
    
    // MARK: - Initialization
    override init() {
        super.init()
        generateTestVideo()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Methods
    
    /// Start the mock camera feed
    func startMockCamera(sampleBufferHandler: @escaping (CMSampleBuffer) -> Void) {
        print("🎬 [SimulatorMock] Starting mock camera...")
        
        guard let testVideoURL = testVideoURL else {
            print("❌ [SimulatorMock] Test video not available")
            return
        }
        
        self.sampleBufferDelegate = sampleBufferHandler
        
        // Create player with looping
        let playerItem = AVPlayerItem(url: testVideoURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Setup video output
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ]
        
        playerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        playerItem.add(playerItemVideoOutput!)
        
        // Setup looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Start playback
        player?.play()
        isActive = true
        
        // Start frame extraction
        startFrameExtraction()
        
        print("✅ [SimulatorMock] Mock camera started successfully")
    }
    
    /// Stop the mock camera feed
    func stopMockCamera() {
        print("🛑 [SimulatorMock] Stopping mock camera...")
        
        stopFrameExtraction()
        player?.pause()
        player = nil
        playerItemVideoOutput = nil
        sampleBufferDelegate = nil
        isActive = false
        
        print("✅ [SimulatorMock] Mock camera stopped")
    }
    
    /// Get a preview layer for the mock camera
    func getPreviewLayer() -> AVPlayerLayer? {
        guard let player = player else { return nil }
        
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    // MARK: - Private Methods
    
    /// Generate a test video programmatically
    private func generateTestVideo() {
        print("🎨 [SimulatorMock] Generating test video...")
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoPath = documentsPath.appendingPathComponent("simulator_test_video.mp4")
        
        // Check if already exists
        if FileManager.default.fileExists(atPath: videoPath.path) {
            print("✅ [SimulatorMock] Test video already exists at: \(videoPath.path)")
            self.testVideoURL = videoPath
            return
        }
        
        // Generate new test video
        Task {
            do {
                try await createTestVideoFile(at: videoPath)
                self.testVideoURL = videoPath
                print("✅ [SimulatorMock] Test video created at: \(videoPath.path)")
            } catch {
                print("❌ [SimulatorMock] Failed to create test video: \(error)")
            }
        }
    }
    
    /// Create a test video file with animated content
    private func createTestVideoFile(at url: URL) async throws {
        let videoWriter = try AVAssetWriter(url: url, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
        ]
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ]
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        videoWriter.add(videoWriterInput)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)
        
        // Generate 5 seconds of video at 30 fps
        let fps: Int32 = 30
        let duration = 5
        let totalFrames = fps * Int32(duration)
        
        await withCheckedContinuation { continuation in
            videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoWriterQueue")) {
                for frame in 0..<totalFrames {
                    guard videoWriterInput.isReadyForMoreMediaData else {
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    
                    let presentationTime = CMTime(value: CMTimeValue(frame), timescale: fps)
                    
                    if let pixelBuffer = self.createTestFramePixelBuffer(frameNumber: Int(frame), totalFrames: Int(totalFrames)) {
                        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                }
                
                videoWriterInput.markAsFinished()
                videoWriter.finishWriting {
                    continuation.resume()
                }
            }
        }
    }
    
    /// Create a pixel buffer with test pattern
    private func createTestFramePixelBuffer(frameNumber: Int, totalFrames: Int) -> CVPixelBuffer? {
        let width = 1920
        let height = 1080
        
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        
        // Draw animated test pattern
        drawTestPattern(in: context, width: width, height: height, frame: frameNumber, totalFrames: totalFrames)
        
        return buffer
    }
    
    /// Draw an animated test pattern
    private func drawTestPattern(in context: CGContext, width: Int, height: Int, frame: Int, totalFrames: Int) {
        let progress = Double(frame) / Double(totalFrames)
        
        // Background gradient
        let colors = [
            UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0).cgColor,
            UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0).cgColor
        ]
        
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: height),
                options: []
            )
        }
        
        // Push context for UIKit drawing
        UIGraphicsPushContext(context)
        
        // Draw title
        let title = "Simulator Test Video"
        let titleFont = UIFont.systemFont(ofSize: 72, weight: .bold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.white
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let titleRect = CGRect(
            x: (CGFloat(width) - titleSize.width) / 2,
            y: CGFloat(height) / 4,
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
        
        // Draw moving circle
        let circleRadius: CGFloat = 50
        let circleX = CGFloat(width) * 0.2 + CGFloat(width) * 0.6 * CGFloat(progress)
        let circleY = CGFloat(height) / 2
        
        UIColor.systemBlue.setFill()
        let circlePath = UIBezierPath(ovalIn: CGRect(
            x: circleX - circleRadius,
            y: circleY - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        ))
        circlePath.fill()
        
        // Draw frame counter
        let frameText = "Frame: \(frame + 1) / \(totalFrames)"
        let frameFont = UIFont.monospacedSystemFont(ofSize: 36, weight: .regular)
        let frameAttributes: [NSAttributedString.Key: Any] = [
            .font: frameFont,
            .foregroundColor: UIColor.white
        ]
        let frameSize = (frameText as NSString).size(withAttributes: frameAttributes)
        let frameRect = CGRect(
            x: (CGFloat(width) - frameSize.width) / 2,
            y: CGFloat(height) * 0.7,
            width: frameSize.width,
            height: frameSize.height
        )
        (frameText as NSString).draw(in: frameRect, withAttributes: frameAttributes)
        
        // Pop context after UIKit drawing
        UIGraphicsPopContext()
    }
    
    /// Start extracting frames from the player
    private func startFrameExtraction() {
        displayLink = CADisplayLink(target: self, selector: #selector(extractFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    /// Stop extracting frames
    private func stopFrameExtraction() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// Extract current frame and convert to CMSampleBuffer
    @objc private func extractFrame() {
        guard let output = playerItemVideoOutput,
              let player = player,
              let currentItem = player.currentItem,
              output.hasNewPixelBuffer(forItemTime: currentItem.currentTime()) else {
            return
        }
        
        let time = currentItem.currentTime()
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return
        }
        
        // Convert CVPixelBuffer to CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMVideoFormatDescription?
        
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let formatDesc = formatDescription else { return }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        if let buffer = sampleBuffer {
            sampleBufferDelegate?(buffer)
        }
    }
    
    /// Capture current frame as UIImage for screenshots
    func captureCurrentFrame() -> UIImage? {
        guard let output = playerItemVideoOutput,
              let player = player,
              let currentItem = player.currentItem,
              output.hasNewPixelBuffer(forItemTime: currentItem.currentTime()) else {
            print("❌ [SimulatorMock] No frame available for screenshot")
            return nil
        }
        
        let time = currentItem.currentTime()
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            print("❌ [SimulatorMock] Failed to copy pixel buffer for screenshot")
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ [SimulatorMock] Failed to create CGImage for screenshot")
            return nil
        }
        
        let image = UIImage(cgImage: cgImage)
        print("✅ [SimulatorMock] Captured screenshot: \(image.size)")
        return image
    }
    
    /// Loop the video when it ends
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        player?.seek(to: .zero)
        player?.play()
    }
    
    /// Cleanup resources
    private func cleanup() {
        stopMockCamera()
        NotificationCenter.default.removeObserver(self)
    }
}

#endif
