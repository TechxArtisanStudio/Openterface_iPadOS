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
    @Published var isTwoFingerScrolling: Bool = false // Track two-finger scroll state
    
    // MARK: - Private Properties
    private let connectionManager: any ConnectionProtocol
    private var lastTapTime: TimeInterval = 0
    private let doubleTapTimeWindow: TimeInterval = 0.3
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
        print("🔍 MouseInputManager initialized")
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
        print("🔍 handleScroll called with deltaX: \(deltaX), deltaY: \(deltaY)")
        print("📜 Performing scroll action - deltaX: \(deltaX), deltaY: \(deltaY)")
        
        // Adjust sensitivity - make scrolling more responsive
        let scrollSensitivity = 3
        let boundedDeltaY = max(-127, min(127, deltaY * scrollSensitivity))
        let boundedDeltaX = max(-127, min(127, deltaX * scrollSensitivity))
        
        print("🔍 After sensitivity adjustment - boundedDeltaX: \(boundedDeltaX), boundedDeltaY: \(boundedDeltaY)")
        
        // For vertical scrolling, use wheelMove (deltaY)
        let wheelMove = boundedDeltaY >= 0 ? boundedDeltaY : (0x100 + boundedDeltaY)
        
        print("🔍 Wheel move value: \(wheelMove) (0x\(String(wheelMove, radix: 16)))")
        
        // Create scroll packet - no mouse button pressed, no movement, just wheel
        var scrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, 0x00, 0x00, UInt8(wheelMove)]
        let sum = scrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        scrollDataPacket.append(UInt8(sum))
        
        print("🔍 Sending scroll packet: \(scrollDataPacket.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        connectionManager.dataTransmission.sendData(Data(scrollDataPacket))
        
        // If there's horizontal scrolling, send a separate packet (if supported)
        if boundedDeltaX != 0 {
            print("🔍 Sending horizontal scroll packet")
            // Some systems support horizontal scrolling via different mechanisms
            // This might need adjustment based on the receiving system
            let horizontalWheel = boundedDeltaX >= 0 ? boundedDeltaX : (0x100 + boundedDeltaX)
            var hScrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, UInt8(horizontalWheel), 0x00, 0x00]
            let hSum = hScrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            hScrollDataPacket.append(UInt8(hSum))
            
            print("🔍 Horizontal scroll packet: \(hScrollDataPacket.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
            connectionManager.dataTransmission.sendData(Data(hScrollDataPacket))
        }
    }
}

// MARK: - MouseInputProtocol Conformance
extension MouseInputManager: MouseInputProtocol {
    func handleInput<T>(_ input: T) {
        print("🔍 MouseInputManager.handleInput called with input type: \(type(of: input))")
        
        if let gestureData = input as? MouseGesture {
            print("🔍 MouseGesture detected - type: \(gestureData.gestureType)")
            print("🔍 Start position: \(gestureData.startPosition)")
            print("🔍 Current position: \(gestureData.currentPosition)")
            print("🔍 End position: \(gestureData.endPosition)")
            
            switch gestureData.gestureType {
            case .tap:
                print("🔍 Processing tap gesture")
                handleClick()
            case .doubleTap:
                print("🔍 Processing double tap gesture")
                handleDoubleClick()
            case .drag:
                print("🔍 Processing drag gesture")
                if let endPosition = gestureData.endPosition {
                    print("🔍 Drag ended at: \(endPosition)")
                    handleDragEnded()
                } else {
                    print("🔍 Drag changed to: \(gestureData.currentPosition)")
                    handleDragChanged(currentPosition: gestureData.currentPosition)
                }
            case .scroll:
                print("🔍 Processing scroll gesture")
                let deltaX = Int(gestureData.currentPosition.x - gestureData.startPosition.x)
                let deltaY = Int(gestureData.currentPosition.y - gestureData.startPosition.y)
                print("🔍 Scroll deltas - X: \(deltaX), Y: \(deltaY)")
                handleScroll(deltaX: deltaX, deltaY: deltaY)
            case .longPress:
                print("🔍 Processing long press gesture (two-finger tap)")
                // Two-finger tap triggers scrolling
                if let endPosition = gestureData.endPosition {
                    print("🔍 Long press with end position - calling handleTwoFingerTap")
                    // If we have end position, calculate scroll delta
                    handleTwoFingerTap(startPosition: gestureData.startPosition, endPosition: endPosition)
                } else {
                    print("🔍 Long press without end position - triggering default scroll")
                    // Default scroll action
                    print("Two-finger tap detected - triggering default scroll")
                    handleScroll(deltaX: 0, deltaY: 10) // Default scroll down
                }
            case .rightClick:
                print("🔍 Processing right click gesture")
                handleRightClick()
            }
        } else {
            print("🔍 Input is not a MouseGesture: \(input)")
        }
    }
    
    func handleMouseMove(delta: CGPoint) {
        print("🔍 handleMouseMove called with delta: \(delta)")
        // Use the new drag changed method for mouse movement
        let currentPos = CGPoint(x: delta.x, y: delta.y)
        handleDragChanged(currentPosition: currentPos)
    }
    
    func handleMouseClick(button: MouseButton, action: MouseAction) {
        print("🔍 handleMouseClick called - button: \(button), action: \(action)")
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
        print("🔍 handleDragGesture called - start: \(start), current: \(current), end: \(String(describing: end))")
        if end != nil {
            handleDragEnded()
        } else {
            handleDragChanged(currentPosition: current)
        }
    }
    
    func handleScroll(delta: CGPoint) {
        print("🔍 handleScroll(delta: CGPoint) called with delta: \(delta)")
        let deltaX = Int(delta.x)
        let deltaY = Int(delta.y)
        handleScroll(deltaX: deltaX, deltaY: deltaY)
    }
}

// MARK: - Public API
extension MouseInputManager {
    /// Handle tap gesture with timing detection
    func handleTap(at position: CGPoint) {
        print("🔍 handleTap called at position: \(position)")
        let currentTime = Date().timeIntervalSince1970
        
        print("🔍 Current time: \(currentTime), Last tap time: \(lastTapTime)")
        print("🔍 Time difference: \(currentTime - lastTapTime)")
        
        if currentTime - lastTapTime < doubleTapTimeWindow {
            // Double tap detected
            print("🔍 Double tap detected")
            handleDoubleClick()
        } else {
            // Single tap
            print("🔍 Single tap detected")
            handleClick()
        }
        
        DispatchQueue.main.async {
            self.lastTapTime = currentTime
        }
    }
    
    /// Handle long press gesture (two finger tap for scrolling)
    func handleLongPress(at position: CGPoint) {
        print("🔍 handleLongPress called at position: \(position)")
        // Two-finger tap should trigger scroll mode
        // For now, implement a default scroll action
        print("Two-finger tap detected - triggering scroll")
        handleScroll(deltaX: 0, deltaY: 10) // Default scroll down (positive Y will be inverted to scroll down)
    }
    
    /// Handle two-finger tap with direction-based scrolling
    func handleTwoFingerTap(startPosition: CGPoint, endPosition: CGPoint) {
        print("🔍 handleTwoFingerTap called")
        print("🔍 Start position: \(startPosition)")
        print("🔍 End position: \(endPosition)")
        
        let deltaX = endPosition.x - startPosition.x
        let deltaY = endPosition.y - startPosition.y
        
        print("🔍 Raw deltas - X: \(deltaX), Y: \(deltaY)")
        
        // Determine scroll direction and magnitude
        let scrollDeltaX = Int(deltaX / 10) // Reduce sensitivity
        let scrollDeltaY = Int(deltaY / 10) // Reduce sensitivity
        
        print("🔍 Calculated scroll deltas - X: \(scrollDeltaX), Y: \(scrollDeltaY)")
        print("Two-finger scroll - deltaX: \(scrollDeltaX), deltaY: \(scrollDeltaY)")
        handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY)
    }
    
    /// Start two-finger scrolling mode
    func startTwoFingerScrolling() {
        print("🔍 startTwoFingerScrolling called")
        DispatchQueue.main.async {
            self.isTwoFingerScrolling = true
            print("🖱️ Two-finger scrolling mode: ON")
        }
    }
    
    /// End two-finger scrolling mode
    func endTwoFingerScrolling() {
        print("🔍 endTwoFingerScrolling called")
        DispatchQueue.main.async {
            self.isTwoFingerScrolling = false
            print("🖱️ Two-finger scrolling mode: OFF")
        }
    }
    
    /// Handle continuous two-finger scrolling
    func handleTwoFingerScrolling(currentPosition: CGPoint) {
        print("🔍 handleTwoFingerScrolling called with position: \(currentPosition)")
        print("🔍 isTwoFingerScrolling state: \(isTwoFingerScrolling)")
        
        guard isTwoFingerScrolling else { 
            print("🔍 Two-finger scrolling not active, returning")
            return 
        }
        
        if let previousPos = previousPosition {
            print("🔍 Previous position: \(previousPos)")
            let deltaX = Int(currentPosition.x - previousPos.x)
            let deltaY = Int(currentPosition.y - previousPos.y)
            
            print("🔍 Raw movement deltas - X: \(deltaX), Y: \(deltaY)")
            
            // Apply scrolling with reduced sensitivity for smooth scrolling
            let scrollSensitivity = 2
            let scrollDeltaX = deltaX / scrollSensitivity
            let scrollDeltaY = deltaY / scrollSensitivity // Remove double inversion - handleScroll will handle the direction
            
            print("🔍 Scroll deltas after sensitivity - X: \(scrollDeltaX), Y: \(scrollDeltaY)")
            
            if abs(scrollDeltaX) > 1 || abs(scrollDeltaY) > 1 {
                print("🔍 Calling handleScroll with deltas - X: \(scrollDeltaX), Y: \(scrollDeltaY)")
                handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY) // Let handleScroll handle the direction
            } else {
                print("🔍 Deltas too small, not scrolling")
            }
        } else {
            print("🔍 No previous position available")
        }
        
        DispatchQueue.main.async {
            self.previousPosition = currentPosition
        }
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
            self.isTwoFingerScrolling = false
            self.lastTapTime = 0
            print("🎯 Mouse state reset")
        }
    }
    
    /// Test method to manually trigger a scroll (for debugging)
    func testScroll() {
        print("🔍 Manual test scroll triggered")
        handleScroll(deltaX: 0, deltaY: 5) // Test scroll down
    }
}
