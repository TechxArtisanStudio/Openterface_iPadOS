import AVFoundation
import UIKit

// Simple test script to check camera authorization
class CameraAuthTest {
    static func test() {
        print("=== Camera Authorization Test ===")
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("Current authorization status: \(status)")
        print("Status raw value: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            print("Status: Not Determined")
        case .restricted:
            print("Status: Restricted")
        case .denied:
            print("Status: Denied")
        case .authorized:
            print("Status: Authorized")
        @unknown default:
            print("Status: Unknown")
        }
        
        print("Is authorized check: \(status == .authorized)")
        
        // Check device availability
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        print("Available video devices: \(devices.count)")
        for device in devices {
            print("- \(device.localizedName) (\(device.deviceType))")
        }
        
        // Try to request permission
        print("Requesting camera permission...")
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                print("Permission request result: \(granted)")
                let newStatus = AVCaptureDevice.authorizationStatus(for: .video)
                print("New authorization status: \(newStatus)")
                print("New is authorized check: \(newStatus == .authorized)")
            }
        }
    }
}
