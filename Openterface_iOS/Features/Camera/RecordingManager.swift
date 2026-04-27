//
//  RecordingManager.swift
//  Openterface_iOS
//
//  Created by Recording System on 10/21/25.
//

import Foundation
import UIKit
import AVFoundation
import Photos
import Combine
import VideoToolbox

/// Manages video recording and screenshot capture for the camera session
final class RecordingManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var lastRecordingInfo: RecordingInfo?
    @Published var lastScreenshotURL: URL?
    
    // MARK: - Configuration
    var configuration: RecordingConfiguration = RecordingConfiguration()
    
    // MARK: - Private Properties
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var recordingStartTime: Date?
    private var currentOutputURL: URL?
    private var isWriting = false
    
    // Photo capture
    private var photoOutput: AVCapturePhotoOutput?
    
    // Keep photo capture delegate alive during capture
    private var activePhotoCaptureDelegate: PhotoCaptureDelegate?
    
    // Timer for duration updates
    private var durationTimer: Timer?
    
    // Timer for frame capture (macOS approach)
    private var recordingTimer: Timer?
    private var frameCount: Int64 = 0
    
    // Latest captured pixel buffer for recording
    private var latestPixelBuffer: CVPixelBuffer?
    private let pixelBufferLock = NSLock()
    
    // Video data output for frame capture during recording
    private var recordingVideoOutput: AVCaptureVideoDataOutput?
    private let recordingQueue = DispatchQueue(label: "com.openterface.recordingQueue")
    
    // Reference to capture session (weak to avoid retain cycle)
    private weak var captureSession: AVCaptureSession?
    
    // Orientation correction mode
    var orientationCorrectionMode: OrientationCorrectionMode = .counterClockwise90
    
    // Audio recording (separate capture session like macOS)
    private var audioCaptureSession: AVCaptureSession?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioQueue: DispatchQueue?
    private var firstAudioTimestamp: CMTime?
    
    // MARK: - Initialization
    override init() {
        super.init()
        Logger.shared.log("RecordingManager initialized", category: .camera)
        checkPhotoLibraryPermission()
    }
    
    deinit {
        cleanup()
        Logger.shared.log("RecordingManager deinitialized", category: .camera)
    }
    
    // MARK: - Permission Management
    
    /// Check current photo library permission status
    private func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            Logger.shared.log("✅ Photo library permission: Authorized", category: .camera)
        case .denied:
            Logger.shared.log("⚠️ Photo library permission: Denied - Screenshots will only be saved to app documents", level: .warning, category: .camera)
        case .restricted:
            Logger.shared.log("⚠️ Photo library permission: Restricted", level: .warning, category: .camera)
        case .notDetermined:
            Logger.shared.log("ℹ️ Photo library permission: Not determined - Will request when saving", category: .camera)
        @unknown default:
            Logger.shared.log("⚠️ Photo library permission: Unknown status", level: .warning, category: .camera)
        }
    }
    
    /// Request photo library permission explicitly
    func requestPhotoLibraryPermission(completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            let isAuthorized = status == .authorized || status == .limited
            Logger.shared.log("Photo library permission request result: \(isAuthorized ? "Granted" : "Denied")", category: .camera)
            DispatchQueue.main.async {
                completion?(isAuthorized)
            }
        }
    }
    
    // MARK: - Public Helper Methods
    
    /// Get the directory where recordings and screenshots are saved
    func getRecordingsDirectory() -> URL {
        let directory = configuration.customOutputDirectory ?? defaultOutputDirectory()
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }
    
    /// Get a user-friendly description of where files are saved
    func getSaveLocationDescription() -> String {
        let dir = getRecordingsDirectory()
        let relativePath = dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return """
        📁 Save Locations:
        1️⃣ App Documents: \(relativePath)
           Access via Files app: On My iPhone/iPad > Openterface KVM > Recordings
        
        2️⃣ Photos App: \(configuration.saveToPhotoLibrary ? "✅ Enabled" : "❌ Disabled")
           \(configuration.saveToPhotoLibrary ? "Screenshots also saved to your Photos library" : "Enable in settings to save to Photos")
        
        💡 Tips:
        • Use Files app to browse all saved files
        • Connect to computer for iTunes File Sharing access
        • Share files directly from Files app
        """
    }
    
    // MARK: - Setup
    
    /// Setup recording manager with a capture session
    func setup(with captureSession: AVCaptureSession) {
        self.captureSession = captureSession
        setupPhotoOutput()
        // Note: We don't setup video data output - we'll capture frames via timer like macOS
        Logger.shared.log("RecordingManager setup complete", category: .camera)
    }
    
    /// Setup photo output for screenshots
    private func setupPhotoOutput() {
        guard let captureSession = captureSession else {
            Logger.shared.log("Cannot setup photo output - no capture session", level: .warning, category: .camera)
            return
        }
        
        let photoOutput = AVCapturePhotoOutput()
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            self.photoOutput = photoOutput
            
            // Enable high resolution capture on the output itself
            photoOutput.isHighResolutionCaptureEnabled = true
            
            Logger.shared.log("Photo output added to session (high resolution: \(photoOutput.isHighResolutionCaptureEnabled))", category: .camera)
        } else {
            Logger.shared.log("Cannot add photo output to session", level: .warning, category: .camera)
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - Video Recording
    
    /// Start video recording
    func startRecording() {
        Logger.shared.log("Starting video recording...", category: .camera)
        
        #if targetEnvironment(simulator)
        // Handle simulator mode separately
        if TARGET_OS_SIMULATOR != 0 && captureSession == nil {
            Logger.shared.log("📱 [Simulator] Starting mock video recording", category: .camera)
            startSimulatorRecording()
            return
        }
        #endif
        
        guard recordingState == .idle else {
            Logger.shared.log("Cannot start recording - state: \(recordingState.description)", level: .warning, category: .camera)
            return
        }
        
        guard captureSession?.isRunning == true else {
            Logger.shared.log("Cannot start recording - session not running", level: .error, category: .camera)
            recordingState = .error(.sessionNotRunning)
            return
        }
        
        recordingState = .preparing
        setupVideoRecording()
    }
    
    /// Setup video recording (macOS approach)
    private func setupVideoRecording() {
        let filename = generateFilename(extension: "mov")
        let outputURL = getRecordingsDirectory().appendingPathComponent(filename)
        currentOutputURL = outputURL
        
        Logger.shared.log("📝 Setting up video recording at: \(outputURL.path)", category: .camera)
        
        // Setup video data output to capture frames
        setupRecordingVideoOutput()
        
        do {
            // Delete existing file if it exists
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            // Create asset writer
            let writer = try AVAssetWriter(url: outputURL, fileType: .mov)
            self.assetWriter = writer
            
            // Setup video input
            if let videoInput = createVideoInput() {
                if writer.canAdd(videoInput) {
                    writer.add(videoInput)
                    self.videoInput = videoInput
                    Logger.shared.log("✅ Video input added to asset writer", category: .camera)
                }
            }
            
            // Setup audio if enabled
            if configuration.includeAudio {
                setupAudioInput()
            }
            
            // Get actual video dimensions from the latest captured frame
            let videoDimensions = getVideoDimensions()
            
            // Setup pixel buffer adaptor for writing frames
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoDimensions.width,
                kCVPixelBufferHeightKey as String: videoDimensions.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            if let videoInput = self.videoInput {
                videoPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
                Logger.shared.log("✅ Pixel buffer adaptor created", category: .camera)
            }
            
            // Start the writer
            if writer.startWriting() {
                writer.startSession(atSourceTime: .zero)
                
                recordingStartTime = Date()
                frameCount = 0
                
                // Set these BEFORE starting audio so audio buffers aren't skipped
                isWriting = true
                recordingState = .recording
                
                // Now start audio capture on background thread - buffers will be accepted now
                if configuration.includeAudio {
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.startAudioRecordingSync()
                        // Small delay to ensure audio session is running before starting timer
                        Thread.sleep(forTimeInterval: 0.1)
                        DispatchQueue.main.async {
                            self?.startRecordingTimer()
                            self?.startDurationTimer()
                        }
                    }
                } else {
                    // No audio, start timer immediately
                    startRecordingTimer()
                    startDurationTimer()
                }
                
                Logger.shared.log("✅ Recording started successfully", category: .camera)
            } else {
                let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
                Logger.shared.log("❌ Writer failed to start: \(errorMsg)", level: .error, category: .camera)
                throw RecordingError.writerSetupFailed
            }
            
        } catch {
            Logger.shared.log("Failed to start recording: \(error)", level: .error, category: .camera)
            recordingState = .error(.writerError(error))
            cleanup()
        }
    }
    
    /// Setup video data output for capturing frames during recording
    private func setupRecordingVideoOutput() {
        guard let captureSession = captureSession else {
            Logger.shared.log("Cannot setup recording video output - no capture session", level: .warning, category: .camera)
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: recordingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = false // Don't drop frames during recording
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            recordingVideoOutput = videoOutput
            Logger.shared.log("✅ Recording video output added to session", category: .camera)
        } else {
            Logger.shared.log("Cannot add recording video output to session", level: .warning, category: .camera)
        }
        
        captureSession.commitConfiguration()
    }
    
    /// Remove video data output after recording
    private func removeRecordingVideoOutput() {
        guard let captureSession = captureSession, let videoOutput = recordingVideoOutput else {
            return
        }
        
        captureSession.beginConfiguration()
        captureSession.removeOutput(videoOutput)
        captureSession.commitConfiguration()
        
        recordingVideoOutput = nil
        latestPixelBuffer = nil
        
        Logger.shared.log("Recording video output removed from session", category: .camera)
    }
    
    /// Setup audio input for asset writer
    private func setupAudioInput() {
        // Audio input settings - optimized for better performance
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        if let audioInput = audioInput, let writer = assetWriter {
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                Logger.shared.log("✅ Audio input added to asset writer", category: .camera)
            }
        }
    }
    
    /// Start audio recording using separate capture session (synchronous version)
    private func startAudioRecordingSync() {
        Logger.shared.log("Setting up audio capture session...", category: .camera)
        
        // Create separate audio capture session
        audioCaptureSession = AVCaptureSession()
        guard let audioCaptureSession = audioCaptureSession else {
            Logger.shared.log("Failed to create audio capture session", level: .error, category: .camera)
            return
        }
        
        audioCaptureSession.sessionPreset = .medium
        audioCaptureSession.beginConfiguration()
        
        // Find audio device
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            Logger.shared.log("No audio device found", level: .warning, category: .camera)
            audioCaptureSession.commitConfiguration()
            return
        }
        
        Logger.shared.log("Found audio device: \(audioDevice.localizedName)", category: .camera)
        
        do {
            // Add audio input
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if audioCaptureSession.canAddInput(audioInput) {
                audioCaptureSession.addInput(audioInput)
                Logger.shared.log("✅ Audio input added to session", category: .camera)
            }
            
            // Add audio data output
            let audioOutput = AVCaptureAudioDataOutput()
            audioQueue = DispatchQueue(label: "com.openterface.audioQueue")
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue!)
            
            if audioCaptureSession.canAddOutput(audioOutput) {
                audioCaptureSession.addOutput(audioOutput)
                audioDataOutput = audioOutput
                Logger.shared.log("✅ Audio data output added to session", category: .camera)
            }
            
            audioCaptureSession.commitConfiguration()
            
            // Start session synchronously (already on background thread from caller)
            audioCaptureSession.startRunning()
            Logger.shared.log("✅ Audio capture session started", category: .camera)
            
        } catch {
            Logger.shared.log("Failed to setup audio: \(error)", level: .error, category: .camera)
            audioCaptureSession.commitConfiguration()
        }
    }
    
    /// Stop audio recording
    private func stopAudioRecording() {
        Logger.shared.log("Stopping audio recording...", category: .camera)
        
        if let audioCaptureSession = audioCaptureSession {
            // Stop session on background thread to avoid blocking UI
            DispatchQueue.global(qos: .userInitiated).async {
                if audioCaptureSession.isRunning {
                    audioCaptureSession.stopRunning()
                }
            }
            
            // Remove outputs and inputs
            audioCaptureSession.outputs.forEach { audioCaptureSession.removeOutput($0) }
            audioCaptureSession.inputs.forEach { audioCaptureSession.removeInput($0) }
            
            self.audioCaptureSession = nil
            self.audioDataOutput = nil
            self.audioQueue = nil
            Logger.shared.log("✅ Audio recording stopped and cleaned up", category: .camera)
        }
    }
    
    /// Start recording timer (30fps like macOS)
    private func startRecordingTimer() {
        frameCount = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.recordFrame()
        }
        Logger.shared.log("✅ Recording timer started at 30fps", category: .camera)
    }
    
    /// Stop recording timer
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        Logger.shared.log("Recording timer stopped", category: .camera)
    }
    
    /// Record a single frame (called by timer at 30fps)
    private func recordFrame() {
        guard isWriting,
              recordingState.isRecording,
              let videoInput = videoInput,
              let adaptor = videoPixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        // Get current pixel buffer from preview layer
        guard let pixelBuffer = captureCurrentPixelBuffer() else {
            return
        }
        
        // Calculate presentation time based on frame count
        let presentationTime = CMTime(value: frameCount, timescale: 30)
        
        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameCount += 1
        } else {
            Logger.shared.log("Failed to append pixel buffer at frame \(frameCount)", level: .warning, category: .camera)
        }
    }
    
    /// Capture current pixel buffer from the preview layer
    private func captureCurrentPixelBuffer() -> CVPixelBuffer? {
        pixelBufferLock.lock()
        defer { pixelBufferLock.unlock() }
        return latestPixelBuffer
    }
    
    /// Stop video recording
    func stopRecording(completion: ((Result<RecordingInfo, RecordingError>) -> Void)? = nil) {
        Logger.shared.log("Stopping video recording...", category: .camera)
        
        #if targetEnvironment(simulator)
        // Handle simulator mode separately
        if TARGET_OS_SIMULATOR != 0 && captureSession == nil {
            Logger.shared.log("📱 [Simulator] Stopping mock video recording", category: .camera)
            stopSimulatorRecording(completion: completion)
            return
        }
        #endif
        
        guard recordingState.isRecording else {
            Logger.shared.log("Cannot stop recording - not recording", level: .warning, category: .camera)
            completion?(.failure(.invalidState))
            return
        }
        
        recordingState = .stopping
        isWriting = false // Stop accepting new buffers immediately
        stopDurationTimer()
        stopRecordingTimer()
        stopAudioRecording()
        
        guard let writer = assetWriter,
              let startTime = recordingStartTime,
              let outputURL = currentOutputURL else {
            Logger.shared.log("Missing writer or recording info", level: .error, category: .camera)
            completion?(.failure(.writerSetupFailed))
            cleanup()
            return
        }
        
        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        Logger.shared.log("🎬 Finishing writing...", category: .camera)
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if writer.status == .completed {
                    let endTime = Date()
                    let duration = endTime.timeIntervalSince(startTime)
                    
                    Logger.shared.log("✅ Recording completed successfully", category: .camera)
                    Logger.shared.log("   Duration: \(duration)s", category: .camera)
                    Logger.shared.log("   File: \(outputURL.path)", category: .camera)
                    
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        
                        let recordingInfo = RecordingInfo(
                            url: outputURL,
                            duration: duration,
                            fileSize: fileSize,
                            startTime: startTime,
                            endTime: endTime
                        )
                        
                        self.lastRecordingInfo = recordingInfo
                        self.recordingState = .idle
                        
                        // Save to photo library if enabled
                        if self.configuration.saveToPhotoLibrary {
                            let authStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                            if authStatus == .authorized || authStatus == .limited {
                                self.saveVideoToPhotoLibrary(url: outputURL)
                            }
                        }
                        
                        completion?(.success(recordingInfo))
                        
                    } catch {
                        Logger.shared.log("Failed to get file info: \(error)", level: .error, category: .camera)
                        completion?(.failure(.fileSystemError(error)))
                    }
                } else {
                    let error = writer.error?.localizedDescription ?? "Unknown error"
                    Logger.shared.log("❌ Recording failed: \(error)", level: .error, category: .camera)
                    self.recordingState = .error(.writerError(writer.error ?? NSError(domain: "RecordingManager", code: -1)))
                    completion?(.failure(.writerError(writer.error ?? NSError(domain: "RecordingManager", code: -1))))
                }
                
                self.cleanup()
            }
        }
    }
    
    // MARK: - Screenshot
    
    /// Capture a screenshot from the current camera feed
    func captureScreenshot(completion: ((Result<URL, RecordingError>) -> Void)? = nil) {
        Logger.shared.log("Capturing screenshot...", category: .camera)
        
        #if targetEnvironment(simulator)
        // Handle simulator mode separately
        if TARGET_OS_SIMULATOR != 0 && captureSession == nil {
            Logger.shared.log("📱 [Simulator] Capturing screenshot from mock camera", category: .camera)
            captureSimulatorScreenshot(completion: completion)
            return
        }
        #endif
        
        guard captureSession?.isRunning == true else {
            Logger.shared.log("Cannot capture screenshot - session not running", level: .error, category: .camera)
            completion?(.failure(.sessionNotRunning))
            return
        }
        
        guard let photoOutput = photoOutput else {
            Logger.shared.log("Photo output not available", level: .error, category: .camera)
            completion?(.failure(.photoOutputNotAvailable))
            return
        }
        
        let settings = AVCapturePhotoSettings()
        
        // Enable high resolution capture only if the output supports it
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }
        
        // Configure photo settings for codec
        let finalSettings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            finalSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            // Enable high resolution for HEVC if supported
            if photoOutput.isHighResolutionCaptureEnabled {
                finalSettings.isHighResolutionPhotoEnabled = true
            }
        } else {
            finalSettings = settings
        }
        
        // Create photo capture delegate
        let delegate = PhotoCaptureDelegate { [weak self] result in
            DispatchQueue.main.async {
                // Clear the reference after completion
                defer { self?.activePhotoCaptureDelegate = nil }
                
                switch result {
                case .success(let imageData):
                    Logger.shared.log("📸 Photo capture successful, image data size: \(imageData.count) bytes", category: .camera)
                    Logger.shared.log("📸 Current orientation correction mode: \(self?.orientationCorrectionMode.rawValue ?? "unknown")", category: .camera)
                    self?.saveScreenshot(imageData: imageData, completion: completion)
                case .failure(let error):
                    Logger.shared.log("Screenshot capture failed: \(error)", level: .error, category: .camera)
                    completion?(.failure(.captureError(error)))
                }
            }
        }
        
        // Keep delegate alive during capture
        self.activePhotoCaptureDelegate = delegate
        
        // Capture photo
        photoOutput.capturePhoto(with: finalSettings, delegate: delegate)
        
        Logger.shared.log("Screenshot capture initiated", category: .camera)
    }
    
    /// Save screenshot to file and optionally to photo library
    private func saveScreenshot(imageData: Data, completion: ((Result<URL, RecordingError>) -> Void)?) {
        do {
            // Convert to UIImage to check and fix orientation
            guard let originalImage = UIImage(data: imageData) else {
                throw NSError(domain: "RecordingManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
            }
            
            // Log detailed orientation information
            Logger.shared.log("═══════════════════════════════════════════════════", category: .camera)
            Logger.shared.log("📸 SCREENSHOT ORIENTATION DEBUG", category: .camera)
            Logger.shared.log("═══════════════════════════════════════════════════", category: .camera)
            Logger.shared.log("Original image size: width=\(originalImage.size.width), height=\(originalImage.size.height)", category: .camera)
            Logger.shared.log("Original orientation: \(getOrientationName(originalImage.imageOrientation)) (rawValue: \(originalImage.imageOrientation.rawValue))", category: .camera)
            Logger.shared.log("Orientation correction mode: \(orientationCorrectionMode.rawValue)", category: .camera)
            Logger.shared.log("Image scale: \(originalImage.scale)", category: .camera)
            
            // Get the actual pixel dimensions from CGImage
            var cgImageWidth = 0
            var cgImageHeight = 0
            if let cgImage = originalImage.cgImage {
                cgImageWidth = cgImage.width
                cgImageHeight = cgImage.height
                Logger.shared.log("CGImage dimensions: width=\(cgImageWidth), height=\(cgImageHeight)", category: .camera)
            }
            
            // Fix orientation - use the ACTUAL pixel dimensions to detect landscape/portrait
            // UIImage.size is already EXIF-adjusted, but we need the raw pixel dimensions
            let correctedImage: UIImage

            // Check if the ACTUAL pixels (cgImage) are landscape
            let isActuallyLandscape = cgImageWidth > cgImageHeight

            if isActuallyLandscape {
                // Camera captured landscape (e.g., 1920x1080)
                // Ignore EXIF rotation, force orientation to .up, apply user-selected rotation
                Logger.shared.log("Landscape camera pixels (\(cgImageWidth)x\(cgImageHeight))", category: .camera)

                if let cgImage = originalImage.cgImage {
                    let baseImage = UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: .up)
                    let angle = orientationCorrectionMode.rotationAngle
                    if angle != 0 {
                        Logger.shared.log("Applying \(angle)° rotation (\(orientationCorrectionMode.description))", category: .camera)
                        if let rotated = rotateImage(baseImage, by: angle) {
                            correctedImage = rotated
                            Logger.shared.log("Image rotated - New size: width=\(rotated.size.width), height=\(rotated.size.height)", category: .camera)
                        } else {
                            correctedImage = baseImage
                            Logger.shared.log("Failed to rotate image, using base", level: .warning, category: .camera)
                        }
                    } else {
                        Logger.shared.log("No rotation needed", category: .camera)
                        correctedImage = baseImage
                    }
                } else {
                    correctedImage = originalImage
                    Logger.shared.log("Failed to get CGImage, using original", level: .warning, category: .camera)
                }
            } else {
                // Camera captured portrait - fix EXIF orientation first, then apply user-selected rotation
                Logger.shared.log("Portrait camera pixels (\(cgImageWidth)x\(cgImageHeight))", category: .camera)

                let baseImage = fixImageOrientation(originalImage)
                let angle = orientationCorrectionMode.rotationAngle
                if angle != 0 {
                    Logger.shared.log("Applying \(angle)° rotation (\(orientationCorrectionMode.description))", category: .camera)
                    if let rotated = rotateImage(baseImage, by: angle) {
                        correctedImage = rotated
                        Logger.shared.log("Image rotated - New size: width=\(rotated.size.width), height=\(rotated.size.height)", category: .camera)
                    } else {
                        correctedImage = baseImage
                        Logger.shared.log("Failed to rotate image, using base", level: .warning, category: .camera)
                    }
                } else {
                    Logger.shared.log("No rotation needed", category: .camera)
                    correctedImage = baseImage
                }
            }

            // Convert to JPEG data
            guard let correctedImageData = correctedImage.jpegData(compressionQuality: 0.95) else {
                throw NSError(domain: "RecordingManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
            }
            
            Logger.shared.log("Final image size: width=\(correctedImage.size.width), height=\(correctedImage.size.height)", category: .camera)
            Logger.shared.log("Final image data size: \(correctedImageData.count) bytes", category: .camera)
            Logger.shared.log("Aspect ratio: \(String(format: "%.2f", correctedImage.size.width / correctedImage.size.height))", category: .camera)
            Logger.shared.log("═══════════════════════════════════════════════════", category: .camera)
            
            // Create output file URL
            let outputURL = createOutputURL(for: "jpg")
            
            // Save to file
            try correctedImageData.write(to: outputURL)
            
            self.lastScreenshotURL = outputURL
            
            Logger.shared.log("✅ Screenshot saved to file: \(outputURL.lastPathComponent)", category: .camera)
            Logger.shared.log("   Full path: \(outputURL.path)", category: .camera)
            
            // Save to photo library if enabled
            if configuration.saveToPhotoLibrary {
                let authStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                
                switch authStatus {
                case .authorized, .limited:
                    // Already authorized, save directly
                    Logger.shared.log("📸 Saving screenshot to photo library...", category: .camera)
                    saveImageToPhotoLibrary(url: outputURL)
                    
                case .notDetermined:
                    // Request permission for the first time
                    Logger.shared.log("📸 Requesting photo library permission...", category: .camera)
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                        if status == .authorized || status == .limited {
                            Logger.shared.log("✅ Photo library permission granted, saving screenshot...", category: .camera)
                            self?.saveImageToPhotoLibrary(url: outputURL)
                        } else {
                            Logger.shared.log("⚠️ Photo library permission denied. Screenshot saved to Files app only.", level: .warning, category: .camera)
                            Logger.shared.log("   To enable later: Settings > Privacy & Security > Photos > Openterface", category: .camera)
                        }
                    }
                    
                case .denied, .restricted:
                    // Permission denied or restricted
                    Logger.shared.log("ℹ️ Screenshot saved to Files app only (Photo library permission denied)", category: .camera)
                    Logger.shared.log("   To enable: Settings > Privacy & Security > Photos > Openterface", category: .camera)
                    
                @unknown default:
                    Logger.shared.log("⚠️ Unknown photo library permission status", level: .warning, category: .camera)
                }
            } else {
                Logger.shared.log("ℹ️ Photo library saving is disabled in configuration", category: .camera)
            }
            
            completion?(.success(outputURL))
            
        } catch {
            Logger.shared.log("Failed to save screenshot: \(error)", level: .error, category: .camera)
            completion?(.failure(.fileSystemError(error)))
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create video input for asset writer  
    private func createVideoInput() -> AVAssetWriterInput? {
        // Get actual video dimensions from the capture session
        let dimensions = getVideoDimensions()
        let width = dimensions.width
        let height = dimensions.height
        
        // SIMPLIFIED: Minimal settings - let system choose defaults
        // The "Operation Interrupted" error might be caused by overly specific codec settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
            // Removed all compression properties to use system defaults
        ]
        
        // Create video input
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true  // Must be true for live capture
        videoInput.transform = CGAffineTransform.identity
        
        Logger.shared.log("Video input created with H.264 (\(width)x\(height))", category: .camera)
        
        return videoInput
    }
    
    /// Create audio input for asset writer
    private func createAudioInput() -> AVAssetWriterInput? {
        // Use 48kHz to match most external audio devices (like Openterface)
        // This avoids resampling and potential format mismatches
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000.0,  // Match device sample rate
            AVEncoderBitRateKey: 128000
        ]
        
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        
        return audioInput
    }
    
    /// Get actual video dimensions from the capture session
    private func getVideoDimensions() -> (width: Int, height: Int) {
        // Try to get dimensions from the latest pixel buffer
        pixelBufferLock.lock()
        if let pixelBuffer = latestPixelBuffer {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            pixelBufferLock.unlock()
            Logger.shared.log("📐 Video dimensions from pixel buffer: \(width)x\(height)", category: .camera)
            return (width, height)
        }
        pixelBufferLock.unlock()
        
        // Fallback: Try to get from capture session's video device input
        if let captureSession = captureSession {
            // Try from any video device input
            for input in captureSession.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    let formatDescription = deviceInput.device.activeFormat.formatDescription
                    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                    let width = Int(dimensions.width)
                    let height = Int(dimensions.height)
                    Logger.shared.log("📐 Video dimensions from device input: \(width)x\(height)", category: .camera)
                    return (width, height)
                }
            }
        }
        
        // Last resort: Default to 1080p (common for external capture devices)
        Logger.shared.log("⚠️ Could not determine video dimensions, using default 1920x1080", level: .warning, category: .camera)
        return (1920, 1080)
    }
    
    /// Create output URL for recording or screenshot
    private func createOutputURL(for fileExtension: String) -> URL {
        let directory = configuration.customOutputDirectory ?? defaultOutputDirectory()
        
        // Create directory if needed
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            Logger.shared.log("✅ Output directory created/verified: \(directory.path)", category: .camera)
        } catch {
            Logger.shared.log("❌ Failed to create output directory: \(error.localizedDescription)", level: .error, category: .camera)
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "Openterface_\(timestamp).\(fileExtension)"
        let outputURL = directory.appendingPathComponent(fileName)
        
        Logger.shared.log("📝 Output URL: \(outputURL.path)", category: .camera)
        
        return outputURL
    }
    
    /// Get default output directory
    private func defaultOutputDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Recordings", isDirectory: true)
    }
    
    /// Start duration timer
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.recordingStartTime else { return }
            
            DispatchQueue.main.async {
                self.currentRecordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    /// Stop duration timer
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        currentRecordingDuration = 0
    }
    
    /// Save video to photo library (only if already authorized)
    private func saveVideoToPhotoLibrary(url: URL) {
        // Only save if already authorized - never request permission during capture
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            if success {
                Logger.shared.log("✅ Video also saved to Photos app", category: .camera)
            } else if let error = error {
                Logger.shared.log("Failed to save video to Photos app: \(error.localizedDescription)", level: .error, category: .camera)
            }
        }
    }
    
    /// Save image to photo library (only if already authorized)
    private func saveImageToPhotoLibrary(url: URL) {
        // Only save if already authorized - never request permission during capture
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }) { success, error in
            if success {
                Logger.shared.log("✅ Screenshot also saved to Photos app", category: .camera)
            } else if let error = error {
                Logger.shared.log("Failed to save screenshot to Photos app: \(error.localizedDescription)", level: .error, category: .camera)
            }
        }
    }
    
    /// Cleanup recording resources
    private func cleanup() {
        // Stop timers
        stopRecordingTimer()
        stopDurationTimer()
        
        // Stop audio recording
        stopAudioRecording()
        
        // Remove recording video output
        removeRecordingVideoOutput()
        
        // Clear writer resources
        videoInput = nil
        videoPixelBufferAdaptor = nil
        audioInput = nil
        assetWriter = nil
        recordingStartTime = nil
        currentOutputURL = nil
        isWriting = false
        firstAudioTimestamp = nil  // Reset audio timestamp baseline
        
        Logger.shared.log("Recording resources cleaned up", category: .camera)
    }
    
    /// Rotate image by specified degrees
    private func rotateImage(_ image: UIImage, by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        
        // Calculate new size
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        
        // Trim off the extremely small float values
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        // Create graphics context
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Move origin to center and rotate
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        
        // Draw image centered at origin
        image.draw(in: CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        ))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
    
    /// Fix image orientation by redrawing it
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // If already in correct orientation, return as-is
        if image.imageOrientation == .up {
            Logger.shared.log("   No fix needed - orientation is already .up", category: .camera)
            return image
        }
        
        Logger.shared.log("   Calculating transform for orientation: \(getOrientationName(image.imageOrientation))", category: .camera)
        
        // Calculate the transform needed
        var transform = CGAffineTransform.identity
        
        switch image.imageOrientation {
        case .down, .downMirrored:
            Logger.shared.log("   Applying 180° rotation (down)", category: .camera)
            transform = transform.translatedBy(x: image.size.width, y: image.size.height)
            transform = transform.rotated(by: .pi)
            
        case .left, .leftMirrored:
            Logger.shared.log("   Applying 90° CW rotation (left)", category: .camera)
            transform = transform.translatedBy(x: image.size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
            
        case .right, .rightMirrored:
            Logger.shared.log("   Applying 90° CCW rotation (right)", category: .camera)
            transform = transform.translatedBy(x: 0, y: image.size.height)
            transform = transform.rotated(by: -.pi / 2)
            
        default:
            Logger.shared.log("   No rotation needed for this orientation", category: .camera)
            break
        }
        
        switch image.imageOrientation {
        case .upMirrored, .downMirrored:
            Logger.shared.log("   Applying horizontal mirror", category: .camera)
            transform = transform.translatedBy(x: image.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            
        case .leftMirrored, .rightMirrored:
            Logger.shared.log("   Applying vertical mirror", category: .camera)
            transform = transform.translatedBy(x: image.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            
        default:
            break
        }
        
        // Create context and draw
        guard let cgImage = image.cgImage,
              let colorSpace = cgImage.colorSpace else {
            return image
        }
        
        guard let context = CGContext(
            data: nil,
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return image
        }
        
        context.concatenate(transform)
        
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: image.size.height, height: image.size.width))
            
        default:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        }
        
        guard let newCGImage = context.makeImage() else {
            Logger.shared.log("   ⚠️ Failed to create new CGImage", level: .warning, category: .camera)
            return image
        }
        
        Logger.shared.log("   ✅ Successfully created corrected image", category: .camera)
        return UIImage(cgImage: newCGImage, scale: image.scale, orientation: .up)
    }
    
    /// Get human-readable orientation name
    private func getOrientationName(_ orientation: UIImage.Orientation) -> String {
        switch orientation {
        case .up: return ".up (0°)"
        case .down: return ".down (180°)"
        case .left: return ".left (90° CCW)"
        case .right: return ".right (90° CW)"
        case .upMirrored: return ".upMirrored (0° + flip)"
        case .downMirrored: return ".downMirrored (180° + flip)"
        case .leftMirrored: return ".leftMirrored (90° CCW + flip)"
        case .rightMirrored: return ".rightMirrored (90° CW + flip)"
        @unknown default: return ".unknown"
        }
    }

    /// Generate filename for recordings
    private func generateFilename(extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Openterface_\(timestamp).\(fileExtension)"
    }
}

// MARK: - Audio Capture Delegate (for separate audio session)

extension RecordingManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle video frames for recording
        if output == recordingVideoOutput {
            // Store the latest pixel buffer for the recording timer to use
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                pixelBufferLock.lock()
                latestPixelBuffer = pixelBuffer
                pixelBufferLock.unlock()
            }
            return
        }
        
        // Handle audio from separate audio session
        if output == audioDataOutput {
            // Track audio buffer count for debugging
            struct AudioStats {
                static var bufferCount = 0
                static var appendedCount = 0
                static var skippedCount = 0
            }
            
            AudioStats.bufferCount += 1
            
            // Check if we're ready to write audio
            guard isWriting,
                  recordingState.isRecording,
                  let audioInput = audioInput,
                  audioInput.isReadyForMoreMediaData else {
                AudioStats.skippedCount += 1
                if AudioStats.bufferCount <= 5 {
                    Logger.shared.log("🎵 Audio buffer #\(AudioStats.bufferCount) skipped - isWriting: \(isWriting), recording: \(recordingState.isRecording), audioInput: \(audioInput != nil), ready: \(audioInput?.isReadyForMoreMediaData ?? false)", level: .warning, category: .camera)
                }
                return
            }
            
            // Get original timestamp
            let originalTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Track first audio timestamp to use as baseline
            if firstAudioTimestamp == nil {
                firstAudioTimestamp = originalTimestamp
                Logger.shared.log("🎵 First audio timestamp recorded: \(originalTimestamp.seconds)s", category: .camera)
            }
            
            // Calculate relative timestamp (starts from 0)
            let relativeTimestamp = CMTimeSubtract(originalTimestamp, firstAudioTimestamp!)
            
            // Log first few audio buffers
            if AudioStats.bufferCount <= 5 {
                Logger.shared.log("🎵 Audio buffer #\(AudioStats.bufferCount) - original: \(originalTimestamp.seconds)s, relative: \(relativeTimestamp.seconds)s", category: .camera)
            }
            
            // Create adjusted audio buffer with relative timestamp
            var adjustedBuffer: CMSampleBuffer?
            var timingInfo = CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sampleBuffer),
                presentationTimeStamp: relativeTimestamp,
                decodeTimeStamp: .invalid
            )
            
            let status = CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleBufferOut: &adjustedBuffer
            )
            
            guard status == noErr, let audioBufferToAppend = adjustedBuffer else {
                Logger.shared.log("❌ Failed to adjust audio buffer timestamp: \(status)", level: .error, category: .camera)
                return
            }
            
            // Append adjusted audio sample buffer
            if audioInput.append(audioBufferToAppend) {
                AudioStats.appendedCount += 1
                if AudioStats.bufferCount <= 5 {
                    Logger.shared.log("✅ Audio buffer #\(AudioStats.bufferCount) appended with relative timestamp (total: \(AudioStats.appendedCount))", category: .camera)
                }
            } else {
                Logger.shared.log("❌ Failed to append audio buffer #\(AudioStats.bufferCount)", level: .error, category: .camera)
            }
        }
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void
    
    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        super.init()
        Logger.shared.log("PhotoCaptureDelegate initialized", category: .camera)
    }
    
    deinit {
        Logger.shared.log("PhotoCaptureDelegate deallocated", category: .camera)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        Logger.shared.log("📸 Photo capture will begin (ID: \(resolvedSettings.uniqueID))", category: .camera)
        Logger.shared.log("   Expected photo dimensions: \(resolvedSettings.photoDimensions.width) x \(resolvedSettings.photoDimensions.height)", category: .camera)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Logger.shared.log("📸 Photo capture finished processing", category: .camera)
        
        if let error = error {
            Logger.shared.log("Photo capture error: \(error)", level: .error, category: .camera)
            completion(.failure(error))
            return
        }
        
        // Log photo metadata
        if let metadata = photo.metadata as? [String: Any] {
            Logger.shared.log("   Photo metadata keys: \(metadata.keys.joined(separator: ", "))", category: .camera)
            if let orientation = metadata[kCGImagePropertyOrientation as String] {
                Logger.shared.log("   EXIF Orientation: \(orientation)", category: .camera)
            }
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            Logger.shared.log("Failed to get image data from photo", level: .error, category: .camera)
            completion(.failure(NSError(domain: "PhotoCaptureDelegate", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data"])))
            return
        }
        
        Logger.shared.log("   Photo data extracted: \(imageData.count) bytes", category: .camera)
        completion(.success(imageData))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            Logger.shared.log("Photo capture finished with error: \(error)", level: .error, category: .camera)
        } else {
            Logger.shared.log("Photo capture completed successfully (ID: \(resolvedSettings.uniqueID))", category: .camera)
        }
    }
}

// MARK: - Simulator Screenshot Support
#if targetEnvironment(simulator)
extension RecordingManager {
    /// Capture screenshot from simulator mock camera
    private func captureSimulatorScreenshot(completion: ((Result<URL, RecordingError>) -> Void)?) {
        Logger.shared.log("📱 [Simulator] Generating placeholder screenshot...", category: .camera)
        
        // Create a simple placeholder image
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Draw gradient background
            let colors = [
                UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0).cgColor,
                UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0).cgColor
            ]
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            
            // Draw text
            let text = "Simulator Screenshot\n\(Date().formatted(date: .abbreviated, time: .standard))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
        
        // Convert to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            Logger.shared.log("❌ [Simulator] Failed to convert image to JPEG", level: .error, category: .camera)
            completion?(.failure(.captureError(NSError(domain: "SimulatorScreenshot", code: -1))))
            return
        }
        
        Logger.shared.log("✅ [Simulator] Screenshot image created: \(imageData.count) bytes", category: .camera)
        saveScreenshot(imageData: imageData, completion: completion)
    }
    
    /// Start simulator recording (mock implementation)
    private func startSimulatorRecording() {
        guard recordingState == .idle else {
            Logger.shared.log("Cannot start simulator recording - state: \(recordingState.description)", level: .warning, category: .camera)
            return
        }
        
        recordingState = .recording
        recordingStartTime = Date()
        
        // Start duration timer
        startDurationTimer()
        
        Logger.shared.log("✅ [Simulator] Mock recording started", category: .camera)
    }
    
    /// Create a short test video file for simulator recording
    private func createSimulatorRecordingVideo(at url: URL, duration: TimeInterval) async throws {
        let videoWriter = try AVAssetWriter(url: url, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
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
        
        // Generate video for the recorded duration at 30 fps
        let fps: Int32 = 30
        let totalFrames = Int32(duration * Double(fps))
        let writerQueue = DispatchQueue(label: "simulatorRecordingWriterQueue", qos: .userInitiated)
        
        Logger.shared.log("⏳ [Simulator] Starting to write \(totalFrames) frames", category: .camera)
        
        try await withCheckedThrowingContinuation { continuation in
            let state = (frameIndex: Int32(0), finished: false)
            let lockQueue = DispatchQueue(label: "com.simulator.frameIndexLock")
            
            var writeMoreFrames: (() -> Void)?
            
            writeMoreFrames = {
                lockQueue.sync {
                    var frameIdx = state.frameIndex
                    var shouldContinue = true
                    
                    while shouldContinue && frameIdx < totalFrames {
                        if !videoWriterInput.isReadyForMoreMediaData {
                            shouldContinue = false
                            break
                        }
                        
                        let presentationTime = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
                        if let pixelBuffer = self.createTestFramePixelBuffer(frameNumber: Int(frameIdx), totalFrames: Int(totalFrames)) {
                            let success = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                            if !success {
                                Logger.shared.log("⚠️ Failed to append pixel buffer for frame \(frameIdx)", level: .warning, category: .camera)
                            }
                        }
                        frameIdx += 1
                    }
                    
                    if frameIdx >= totalFrames && !state.finished {
                        Logger.shared.log("✅ All \(frameIdx) frames appended, marking as finished", category: .camera)
                        videoWriterInput.markAsFinished()
                        
                        videoWriter.finishWriting {
                            if videoWriter.status == .completed {
                                Logger.shared.log("✅ Simulator video writing completed successfully", category: .camera)
                                continuation.resume()
                            } else if let error = videoWriter.error {
                                Logger.shared.log("❌ Video writing failed: \(error.localizedDescription)", level: .error, category: .camera)
                                continuation.resume(throwing: error)
                            } else {
                                let error = NSError(domain: "RecordingManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown video writing error"])
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
            
            videoWriterInput.requestMediaDataWhenReady(on: writerQueue, using: writeMoreFrames!)
        }
    }
    
    /// Create a pixel buffer with test pattern for simulator recording
    private func createTestFramePixelBuffer(frameNumber: Int, totalFrames: Int) -> CVPixelBuffer? {
        let width = 1920
        let height = 1080
        
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        // Fill with animated color pattern
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bufferPointer = baseAddress.assumingMemoryBound(to: UInt32.self)
            let progress = Double(frameNumber) / Double(totalFrames)
            let intensity = UInt8(progress * 255)
            
            // Create BGRA color: Blue changes, Red stays high, Green low, Alpha full
            let blue = intensity
            let green: UInt8 = 50
            let red: UInt8 = 200
            let alpha: UInt8 = 255
            
            let pixelValue: UInt32 = UInt32(blue) | (UInt32(green) << 8) | (UInt32(red) << 16) | (UInt32(alpha) << 24)
            
            for i in 0..<width * height {
                bufferPointer[i] = pixelValue
            }
        }
        
        return buffer
    }
    
    /// Stop simulator recording (mock implementation)
    private func stopSimulatorRecording(completion: ((Result<RecordingInfo, RecordingError>) -> Void)?) {
        guard recordingState.isRecording else {
            Logger.shared.log("Cannot stop simulator recording - not recording", level: .warning, category: .camera)
            completion?(.failure(.invalidState))
            return
        }
        
        recordingState = .idle
        stopDurationTimer()
        
        guard let startTime = recordingStartTime else {
            Logger.shared.log("Missing recording start time", level: .error, category: .camera)
            completion?(.failure(.invalidState))
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        Logger.shared.log("📱 [Simulator] Recording stopped - duration: \(duration)s", category: .camera)
        
        // Create a real video file for simulator mode
        let outputURL = createOutputURL(for: "mp4")
        
        Logger.shared.log("📝 [Simulator] Starting video file creation at: \(outputURL.path)", category: .camera)
        
        Task {
            var recordingInfo: RecordingInfo
            
            do {
                Logger.shared.log("⏳ [Simulator] Creating video file...", category: .camera)
                try await self.createSimulatorRecordingVideo(at: outputURL, duration: duration)
                
                // Verify file was created
                let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
                Logger.shared.log("✅ [Simulator] Video file creation completed. File exists: \(fileExists)", category: .camera)
                
                if fileExists {
                    Logger.shared.log("✅ [Simulator] Created recording video file: \(outputURL.lastPathComponent)", category: .camera)
                } else {
                    Logger.shared.log("❌ [Simulator] Video file was not created at \(outputURL.path)", level: .error, category: .camera)
                }
                
                // Get actual file size
                let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0
                
                Logger.shared.log("📊 [Simulator] File size: \(fileSize) bytes", category: .camera)
                
                recordingInfo = RecordingInfo(
                    url: outputURL,
                    duration: duration,
                    fileSize: fileSize,
                    startTime: startTime,
                    endTime: endTime
                )
            } catch {
                Logger.shared.log("❌ [Simulator] Failed to create recording video: \(error.localizedDescription)", level: .error, category: .camera)
                
                recordingInfo = RecordingInfo(
                    url: outputURL,
                    duration: duration,
                    fileSize: 0,
                    startTime: startTime,
                    endTime: endTime
                )
            }
            
            self.lastRecordingInfo = recordingInfo
            
            Logger.shared.log("✅ [Simulator] Mock recording stopped: \(recordingInfo.durationFormatted)", category: .camera)
            completion?(.success(recordingInfo))
        }
    }
}
#endif
