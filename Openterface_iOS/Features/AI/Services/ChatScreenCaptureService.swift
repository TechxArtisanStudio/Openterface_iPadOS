//
//  ChatScreenCaptureService.swift
//  Openterface_iOS
//

import Foundation

final class ChatScreenCaptureService {

    private let cameraManager: CameraSessionManager

    init(cameraManager: CameraSessionManager) {
        self.cameraManager = cameraManager
    }

    func captureScreenForAgent() async -> URL? {
        await withCheckedContinuation { continuation in
            cameraManager.captureScreenshot { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
