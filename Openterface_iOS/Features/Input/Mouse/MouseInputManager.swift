//
//  MouseInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreGraphics

final class MouseInputManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false
    
    // MARK: - Private Properties
    private let connectionManager: any ConnectionProtocol
    private var lastTapTime: TimeInterval = 0
    private let doubleTapTimeWindow: TimeInterval = 0.3
    private let mouseSensitivity: Float = 2.0
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
    }
}

// MARK: - MouseInputProtocol Conformance
extension MouseInputManager: MouseInputProtocol {
    func handleInput<T>(_ input: T) {
        if let gestureData = input as? MouseGesture {
            switch gestureData.gestureType {
            case .tap:
                handleMouseClick(button: .left, action: .click)
            case .doubleTap:
                handleMouseClick(button: .left, action: .doubleClick)
            case .drag:
                if let endPosition = gestureData.endPosition {
                    handleDragGesture(start: gestureData.startPosition, current: gestureData.currentPosition, end: endPosition)
                } else {
                    handleDragGesture(start: gestureData.startPosition, current: gestureData.currentPosition, end: nil)
                }
            case .scroll:
                let delta = CGPoint(
                    x: gestureData.currentPosition.x - gestureData.startPosition.x,
                    y: gestureData.currentPosition.y - gestureData.startPosition.y
                )
                handleScroll(delta: delta)
            case .longPress:
                handleMouseClick(button: .right, action: .click)
            }
        }
    }
    
    func handleMouseMove(delta: CGPoint) {
        let xDelta = Int(delta.x * CGFloat(mouseSensitivity))
        let yDelta = Int(delta.y * CGFloat(mouseSensitivity))
        
        // Clamp values to Int8 range
        let clampedX = Int8(clamping: xDelta)
        let clampedY = Int8(clamping: yDelta)
        
        sendMouseMove(dx: Int(clampedX), dy: Int(clampedY))
    }
    
    func handleMouseClick(button: MouseButton, action: MouseAction) {
        print("🖱️ Mouse \(button) \(action)")
        
        switch action {
        case .click:
            sendMouseClick(button: button)
        case .doubleClick:
            sendMouseDoubleClick(button: button)
        case .press:
            sendMousePress(button: button)
        case .release:
            sendMouseRelease(button: button)
        }
    }
    
    func handleDragGesture(start: CGPoint, current: CGPoint, end: CGPoint?) {
        if let end = end {
            // Drag ended
            currentPosition = nil
            isSelectMode = false
            print("🖱️ Drag gesture ended")
        } else {
            // Drag in progress
            if currentPosition == nil {
                currentPosition = start
                isSelectMode = true
                print("🖱️ Drag gesture started")
            } else {
                let delta = CGPoint(
                    x: current.x - (currentPosition?.x ?? start.x),
                    y: current.y - (currentPosition?.y ?? start.y)
                )
                handleMouseMove(delta: delta)
                currentPosition = current
            }
        }
    }
    
    func handleScroll(delta: CGPoint) {
        let scrollX = Int8(clamping: Int(delta.x))
        let scrollY = Int8(clamping: Int(delta.y))
        
        sendMouseScroll(dx: Int(scrollX), dy: Int(scrollY))
    }
}

// MARK: - Private Methods
private extension MouseInputManager {
    func sendMouseMove(dx: Int, dy: Int) {
        var dx8 = Int8(clamping: dx)
        var dy8 = Int8(clamping: dy)
        let data = Data(bytes: &dx8, count: 1) + Data(bytes: &dy8, count: 1)
        
        connectionManager.dataTransmission.sendData(data)
        print("🖱️ Mouse move sent: dx=\(dx8), dy=\(dy8)")
    }
    
    func sendMouseClick(button: MouseButton) {
        let buttonCode = getButtonCode(for: button)
        var data = Data([buttonCode])
        
        // Send press
        connectionManager.dataTransmission.sendData(data)
        
        // Send release after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.connectionManager.dataTransmission.sendData(Data([0x00]))
        }
        
        print("🖱️ Mouse click sent: button=\(button)")
    }
    
    func sendMouseDoubleClick(button: MouseButton) {
        let buttonCode = getButtonCode(for: button)
        
        // First click
        connectionManager.dataTransmission.sendData(Data([buttonCode]))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.connectionManager.dataTransmission.sendData(Data([0x00]))
        }
        
        // Second click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connectionManager.dataTransmission.sendData(Data([buttonCode]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.connectionManager.dataTransmission.sendData(Data([0x00]))
            }
        }
        
        print("🖱️ Mouse double click sent: button=\(button)")
    }
    
    func sendMousePress(button: MouseButton) {
        let buttonCode = getButtonCode(for: button)
        connectionManager.dataTransmission.sendData(Data([buttonCode]))
        print("🖱️ Mouse press sent: button=\(button)")
    }
    
    func sendMouseRelease(button: MouseButton) {
        connectionManager.dataTransmission.sendData(Data([0x00]))
        print("🖱️ Mouse release sent")
    }
    
    func sendMouseScroll(dx: Int, dy: Int) {
        var dx8 = Int8(clamping: dx)
        var dy8 = Int8(clamping: dy)
        let data = Data([0x00, 0x00]) + Data(bytes: &dx8, count: 1) + Data(bytes: &dy8, count: 1)
        
        connectionManager.dataTransmission.sendData(data)
        print("🖱️ Mouse scroll sent: dx=\(dx8), dy=\(dy8)")
    }
    
    func getButtonCode(for button: MouseButton) -> UInt8 {
        switch button {
        case .left: return 0x01
        case .right: return 0x02
        case .middle: return 0x04
        }
    }
}

// MARK: - Public API
extension MouseInputManager {
    /// Handle tap gesture with timing detection
    func handleTap(at position: CGPoint) {
        let currentTime = Date().timeIntervalSince1970
        
        if currentTime - lastTapTime < doubleTapTimeWindow {
            // Double tap detected
            handleMouseClick(button: .left, action: .doubleClick)
        } else {
            // Single tap
            handleMouseClick(button: .left, action: .click)
        }
        
        lastTapTime = currentTime
    }
    
    /// Handle long press gesture
    func handleLongPress(at position: CGPoint) {
        handleMouseClick(button: .right, action: .click)
    }
    
    /// Toggle selection mode
    func toggleSelectMode() {
        isSelectMode.toggle()
        print("🎯 Select mode: \(isSelectMode ? "ON" : "OFF")")
    }
    
    /// Reset mouse state
    func resetState() {
        currentPosition = nil
        isSelectMode = false
        lastTapTime = 0
    }
}
