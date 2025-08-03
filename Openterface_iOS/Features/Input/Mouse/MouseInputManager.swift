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
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false // Track drag mode state
    
    // MARK: - Private Properties
    private let connectionManager: any ConnectionProtocol
    private var lastTapTime: TimeInterval = 0
    private let doubleTapTimeWindow: TimeInterval = 0.3
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
    }
    
    // MARK: - Drag Event Handlers
    func handleDragChanged(currentPosition: CGPoint) {
        var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
        var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
        
        // Update both positions on main thread to avoid UI update issues
        DispatchQueue.main.async {
            self.currentPosition = currentPosition
            self.previousPosition = currentPosition
        }
        
        let mousePressed = isSelectMode ? 0x01 : 0x00 // Use drag mode state
        let wheelMove = 0x00
        xDelta *= 4
        yDelta *= 4
        let boundedXDelta = max(-127, min(127, xDelta))
        let boundedYDelta = max(-127, min(127, yDelta))
        let xDirection = boundedXDelta >= 0 ? boundedXDelta : (0x100 + boundedXDelta)
        let yDirection = boundedYDelta >= 0 ? boundedYDelta : (0x100 + boundedYDelta)
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), UInt8(xDirection), UInt8(yDirection), UInt8(wheelMove)]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func handleDragEnded() {
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
        }
        if !isSelectMode {
            let mouseReleased = 0x00
            let dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00, 0x63]
            connectionManager.dataTransmission.sendData(Data(dataPacket))
        }
    }

    func handleDoubleClick() {
        print("Performing double click action")
        
        // Send first click
        let mousePressed = 0x01
        var clickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
        let sum = clickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        clickDataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(clickDataPacket))
        
        // Release first click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.connectionManager.dataTransmission.sendData(Data(releaseDataPacket))
            
            // Send second click after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                var secondClickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
                let secondSum = secondClickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                secondClickDataPacket.append(UInt8(secondSum))
                self.connectionManager.dataTransmission.sendData(Data(secondClickDataPacket))
                
                // Release second click
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    var secondReleaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
                    let secondReleaseSum = secondReleaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                    secondReleaseDataPacket.append(UInt8(secondReleaseSum))
                    self.connectionManager.dataTransmission.sendData(Data(secondReleaseDataPacket))
                }
            }
        }
    }
    
    func handleDragModeToggle() {
        let newSelectMode = !isSelectMode
        DispatchQueue.main.async {
            self.isSelectMode = newSelectMode
            print("Drag mode: \(newSelectMode ? "ON" : "OFF")")
        }
        
        // Send appropriate mouse state using the new value
        let mouseState = newSelectMode ? 0x01 : 0x00
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func handleRightClick() {
        print("Performing right click action")
        
        // Send a right click event (press and release)
        // Right click is usually button 2 (0x02)
        let rightMousePressed = 0x02
        var rightClickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(rightMousePressed), 0x00, 0x00, 0x00]
        let sum = rightClickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        rightClickDataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(rightClickDataPacket))
        
        // Small delay and then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.connectionManager.dataTransmission.sendData(Data(releaseDataPacket))
        }
    }

    func handleClick() {
        print("Performing click action")
        
        // Send a click event (press and release)
        let mousePressed = 0x01
        var clickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
        let sum = clickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        clickDataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(clickDataPacket))
        
        // Small delay and then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.connectionManager.dataTransmission.sendData(Data(releaseDataPacket))
        }
    }

    func handleScroll(deltaX: Int, deltaY: Int) {
        print("Performing scroll action - deltaX: \(deltaX), deltaY: \(deltaY)")
        
        // Convert scroll deltas to appropriate wheel values
        // Positive deltaY means scroll up, negative means scroll down
        // Adjust sensitivity - make scrolling more responsive
        let scrollSensitivity = 3
        let boundedDeltaY = max(-127, min(127, deltaY * scrollSensitivity))
        let boundedDeltaX = max(-127, min(127, deltaX * scrollSensitivity))
        
        // For vertical scrolling, use wheelMove (deltaY)
        let wheelMove = boundedDeltaY >= 0 ? boundedDeltaY : (0x100 + boundedDeltaY)
        
        // Create scroll packet - no mouse button pressed, no movement, just wheel
        var scrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, 0x00, 0x00, UInt8(wheelMove)]
        let sum = scrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        scrollDataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(scrollDataPacket))
        
        // If there's horizontal scrolling, send a separate packet (if supported)
        if boundedDeltaX != 0 {
            // Some systems support horizontal scrolling via different mechanisms
            // This might need adjustment based on the receiving system
            let horizontalWheel = boundedDeltaX >= 0 ? boundedDeltaX : (0x100 + boundedDeltaX)
            var hScrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, UInt8(horizontalWheel), 0x00, 0x00]
            let hSum = hScrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            hScrollDataPacket.append(UInt8(hSum))
            connectionManager.dataTransmission.sendData(Data(hScrollDataPacket))
        }
    }
}

// MARK: - MouseInputProtocol Conformance
extension MouseInputManager: MouseInputProtocol {
    func handleInput<T>(_ input: T) {
        if let gestureData = input as? MouseGesture {
            switch gestureData.gestureType {
            case .tap:
                handleClick()
            case .doubleTap:
                handleDoubleClick()
            case .drag:
                if let endPosition = gestureData.endPosition {
                    handleDragEnded()
                } else {
                    handleDragChanged(currentPosition: gestureData.currentPosition)
                }
            case .scroll:
                let deltaX = Int(gestureData.currentPosition.x - gestureData.startPosition.x)
                let deltaY = Int(gestureData.currentPosition.y - gestureData.startPosition.y)
                handleScroll(deltaX: deltaX, deltaY: deltaY)
            case .longPress:
                handleRightClick()
            case .rightClick:
                handleRightClick()
            }
        }
    }
    
    func handleMouseMove(delta: CGPoint) {
        // Use the new drag changed method for mouse movement
        let currentPos = CGPoint(x: delta.x, y: delta.y)
        handleDragChanged(currentPosition: currentPos)
    }
    
    func handleMouseClick(button: MouseButton, action: MouseAction) {
        print("🖱️ Mouse \(button) \(action)")
        
        switch (button, action) {
        case (.left, .click):
            handleClick()
        case (.left, .doubleClick):
            handleDoubleClick()
        case (.right, .click):
            handleRightClick()
        case (.left, .press):
            DispatchQueue.main.async {
                self.isSelectMode = true
            }
            // Send mouse press state directly
            let mouseState = 0x01
            var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
            let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            dataPacket.append(UInt8(sum))
            connectionManager.dataTransmission.sendData(Data(dataPacket))
        case (.left, .release):
            DispatchQueue.main.async {
                self.isSelectMode = false
            }
            // Send mouse release state directly
            let mouseState = 0x00
            var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
            let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            dataPacket.append(UInt8(sum))
            connectionManager.dataTransmission.sendData(Data(dataPacket))
        default:
            // Handle other combinations if needed
            break
        }
    }
    
    func handleDragGesture(start: CGPoint, current: CGPoint, end: CGPoint?) {
        if let end = end {
            handleDragEnded()
        } else {
            handleDragChanged(currentPosition: current)
        }
    }
    
    func handleScroll(delta: CGPoint) {
        let deltaX = Int(delta.x)
        let deltaY = Int(delta.y)
        handleScroll(deltaX: deltaX, deltaY: deltaY)
    }
}

// MARK: - Public API
extension MouseInputManager {
    /// Handle tap gesture with timing detection
    func handleTap(at position: CGPoint) {
        let currentTime = Date().timeIntervalSince1970
        
        if currentTime - lastTapTime < doubleTapTimeWindow {
            // Double tap detected
            handleDoubleClick()
        } else {
            // Single tap
            handleClick()
        }
        
        DispatchQueue.main.async {
            self.lastTapTime = currentTime
        }
    }
    
    /// Handle long press gesture (two finger tap for right click)
    func handleLongPress(at position: CGPoint) {
        handleRightClick()
    }
    
    /// Toggle selection mode
    func toggleSelectMode() {
        let newSelectMode = !isSelectMode
        DispatchQueue.main.async {
            self.isSelectMode = newSelectMode
            print("Drag mode: \(newSelectMode ? "ON" : "OFF")")
        }
        
        // Send appropriate mouse state using the new value
        let mouseState = newSelectMode ? 0x01 : 0x00
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }
    
    /// Reset mouse state
    func resetState() {
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
            self.isSelectMode = false
            self.lastTapTime = 0
            print("🎯 Mouse state reset")
        }
    }
}
