//
//  MouseInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreGraphics

final class MouseInputManager: ObservableObject {
    private let logger = Logger.shared
    // MARK: - Published Properties
    @Published var currentPosition: CGPoint? = nil
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false // Track drag mode state
    @Published var isTwoFingerScrolling: Bool = false // Track two-finger scroll state
    
    // MARK: - Private Properties
    private let connectionManager: any ConnectionProtocol
    private var lastTapTime: TimeInterval = 0
    private let doubleTapTimeWindow: TimeInterval = 0.3
    private var dragStartPosition: CGPoint = .zero
    private var isDragInProgress: Bool = false
    private var lastProcessedDragPosition: CGPoint = .zero  // For deduplication
    private var internalPreviousPosition: CGPoint = .zero  // For synchronous delta calculation
    private let dragQueue = DispatchQueue(label: "com.openterface.mouse.drag", qos: .userInteractive)  // Serial queue for drag synchronization
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
        logger.debug("MouseInputManager initialized", category: .mouse)
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
        isDragInProgress = false
        dragStartPosition = .zero  // Reset for next drag
        lastProcessedDragPosition = .zero  // Reset deduplication state
        internalPreviousPosition = .zero  // Reset internal tracking
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
            self.isSelectMode = false
        }
        let mouseReleased = 0x00
        let dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00, 0x63]
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func handleDoubleClick() {
        logger.debug("Performing double click action", category: .mouse)
        
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
            self.logger.debug("Drag mode: \(newSelectMode ? "ON" : "OFF")", category: .mouse)
        }
        
        // Send appropriate mouse state using the new value
        let mouseState = newSelectMode ? 0x01 : 0x00
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func enterDraggingMode() {
        DispatchQueue.main.async {
            self.isSelectMode = true
            self.logger.debug("Entered dragging mode", category: .mouse)
        }
        
        // Send mouse press
        let mousePressed = 0x01
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func exitDraggingMode() {
        DispatchQueue.main.async {
            self.isSelectMode = false
            self.logger.debug("Exited dragging mode", category: .mouse)
        }
        
        // Send mouse release
        let mouseReleased = 0x00
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        connectionManager.dataTransmission.sendData(Data(dataPacket))
    }

    func handleRightClick() {
        logger.debug("Performing right click action", category: .mouse)
        
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
        logger.debug("Performing click action", category: .mouse)
        
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
        logger.debug("handleScroll called with deltaX: \(deltaX), deltaY: \(deltaY)", category: .mouse)
        
        // Adjust sensitivity - make scrolling less sensitive
        let scrollSensitivity = 2
        let boundedDeltaY = max(-127, min(127, deltaY * scrollSensitivity))
        let boundedDeltaX = max(-127, min(127, deltaX * scrollSensitivity))
        
        logger.debug("After sensitivity adjustment - boundedDeltaX: \(boundedDeltaX), boundedDeltaY: \(boundedDeltaY)", category: .mouse)
        
        // For vertical scrolling, use wheelMove (deltaY)
        let wheelMove = boundedDeltaY >= 0 ? boundedDeltaY : (0x100 + boundedDeltaY)
        
        logger.debug("Wheel move value: \(wheelMove) (0x\(String(wheelMove, radix: 16)))", category: .mouse)
        
        // Create scroll packet - no mouse button pressed, no movement, just wheel
        var scrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, 0x00, 0x00, UInt8(wheelMove)]
        let sum = scrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        scrollDataPacket.append(UInt8(sum))
        
        logger.debug("Sending scroll packet: \(scrollDataPacket.map { String(format: "0x%02X", $0) }.joined(separator: " "))", category: .mouse)
        connectionManager.dataTransmission.sendData(Data(scrollDataPacket))
        
        // If there's horizontal scrolling, send a separate packet (if supported)
        if boundedDeltaX != 0 {
            logger.debug("Sending horizontal scroll packet", category: .mouse)
            // Some systems support horizontal scrolling via different mechanisms
            // This might need adjustment based on the receiving system
            let horizontalWheel = boundedDeltaX >= 0 ? boundedDeltaX : (0x100 + boundedDeltaX)
            var hScrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, UInt8(horizontalWheel), 0x00, 0x00]
            let hSum = hScrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            hScrollDataPacket.append(UInt8(hSum))
            
            logger.debug("Horizontal scroll packet: \(hScrollDataPacket.map { String(format: "0x%02X", $0) }.joined(separator: " "))", category: .mouse)
            connectionManager.dataTransmission.sendData(Data(hScrollDataPacket))
        }
    }
}

// MARK: - MouseInputProtocol Conformance
extension MouseInputManager: MouseInputProtocol {
    func handleInput<T>(_ input: T) {
        logger.debug("MouseInputManager.handleInput called with input type: \(type(of: input))", category: .mouse)
        
        if let gestureData = input as? MouseGesture {
            logger.debug("MouseGesture detected - type: \(gestureData.gestureType)", category: .mouse)
            logger.debug("Start position: \(gestureData.startPosition)", category: .mouse)
            logger.debug("Current position: \(gestureData.currentPosition)", category: .mouse)
            logger.debug("End position: \(gestureData.endPosition)", category: .mouse)
            
            switch gestureData.gestureType {
            case .tap:
                logger.debug("Processing tap gesture", category: .mouse)
                handleClick()
            case .doubleTap:
                logger.debug("Processing double tap gesture", category: .mouse)
                handleDoubleClick()
            case .drag:
                logger.debug("Processing drag gesture", category: .mouse)
                if let endPosition = gestureData.endPosition {
                    logger.debug("Drag ended at: \(endPosition)", category: .mouse)
                    handleDragEnded()
                } else {
                    logger.debug("Drag changed to: \(gestureData.currentPosition)", category: .mouse)
                    handleDragChanged(currentPosition: gestureData.currentPosition)
                }
            case .scroll:
                logger.debug("Processing scroll gesture", category: .mouse)
                let deltaX = Int(gestureData.currentPosition.x - gestureData.startPosition.x)
                let deltaY = Int(gestureData.currentPosition.y - gestureData.startPosition.y)
                logger.debug("Scroll deltas - X: \(deltaX), Y: \(deltaY)", category: .mouse)
                handleScroll(deltaX: deltaX, deltaY: deltaY)
            case .longPress:
                logger.debug("Processing long press gesture (two-finger tap)", category: .mouse)
                // Two-finger tap triggers scrolling
                if let endPosition = gestureData.endPosition {
                    logger.debug("Long press with end position - calling handleTwoFingerTap", category: .mouse)
                    // If we have end position, calculate scroll delta
                    handleTwoFingerTap(startPosition: gestureData.startPosition, endPosition: endPosition)
                } else {
                    logger.debug("Long press without end position - triggering default scroll", category: .mouse)
                    // Default scroll action
                    logger.info("Two-finger tap detected - triggering default scroll", category: .mouse)
                    handleScroll(deltaX: 0, deltaY: 10) // Default scroll down
                }
            case .rightClick:
                logger.debug("Processing right click gesture", category: .mouse)
                handleRightClick()
            }
        } else {
            logger.debug("Input is not a MouseGesture: \(input)", category: .mouse)
        }
    }
    
    func handleMouseMove(delta: CGPoint) {
        logger.debug("handleMouseMove called with delta: \(delta)", category: .mouse)
        // Use the new drag changed method for mouse movement
        let currentPos = CGPoint(x: delta.x, y: delta.y)
        handleDragChanged(currentPosition: currentPos)
    }
    
    func handleMouseClick(button: MouseButton, action: MouseAction) {
        logger.debug("handleMouseClick called - button: \(button), action: \(action)", category: .mouse)
        logger.info("Mouse \(button) \(action)", category: .mouse)
        
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
    
    /// Reset drag state synchronously - called when a new gesture begins
    func resetDragState() {
        isDragInProgress = false
        dragStartPosition = .zero
        lastProcessedDragPosition = .zero
        internalPreviousPosition = .zero
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
        }
        logger.debug("Drag state reset", category: .mouse)
    }
    
    func handleDragGesture(start: CGPoint, current: CGPoint, end: CGPoint?) {
        // Use serial queue to prevent race conditions from duplicate gesture calls
        dragQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.debug("handleDragGesture called - start: \(start), current: \(current), end: \(String(describing: end)), isDragInProgress: \(self.isDragInProgress)", category: .mouse)
            
            if end != nil {
                self.handleDragEnded()
            } else {
                // On the first call of a new drag (when isDragInProgress is false), initialize it
                if !self.isDragInProgress {
                    self.dragStartPosition = start
                    self.lastProcessedDragPosition = start
                    self.internalPreviousPosition = start  // Initialize internal tracking
                    self.isDragInProgress = true
                    DispatchQueue.main.async {
                        self.currentPosition = start
                        self.previousPosition = start
                    }
                    self.logger.debug("First drag - initialized positions to start: \(start)", category: .mouse)
                    // Don't send movement on first call - just initialize positions
                    return
                }
                
                // Deduplication: Skip if this is the same position as the last processed drag
                if current == self.lastProcessedDragPosition {
                    self.logger.debug("Skipping duplicate drag gesture at position: \(current)", category: .mouse)
                    return
                }
                
                // Calculate incremental delta from the internal previous position (synchronous, no race condition)
                let xDelta = Int(current.x - self.internalPreviousPosition.x)
                let yDelta = Int(current.y - self.internalPreviousPosition.y)
                
                self.logger.debug("Calculated incremental deltas - xDelta: \(xDelta), yDelta: \(yDelta)", category: .mouse)
                
                // Update internal tracking position immediately (synchronous in serial queue)
                self.internalPreviousPosition = current
                
                // Update last processed position for deduplication
                self.lastProcessedDragPosition = current
                
                // Update published properties on main thread for UI updates
                DispatchQueue.main.async {
                    self.currentPosition = current
                    self.previousPosition = current
                }
                
                let mousePressed = self.isSelectMode ? 0x01 : 0x00
                let wheelMove = 0x00
                // Use minimal scaling - the deltas are already in screen pixels
                let boundedXDelta = max(-127, min(127, xDelta))
                let boundedYDelta = max(-127, min(127, yDelta))
                let xDirection = boundedXDelta >= 0 ? boundedXDelta : (0x100 + boundedXDelta)
                let yDirection = boundedYDelta >= 0 ? boundedYDelta : (0x100 + boundedYDelta)
                var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), UInt8(xDirection), UInt8(yDirection), UInt8(wheelMove)]
                let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                dataPacket.append(UInt8(sum))
                self.logger.debug("Sending movement packet - xDir: \(xDirection), yDir: \(yDirection)", category: .mouse)
                self.connectionManager.dataTransmission.sendData(Data(dataPacket))
            }
        }
    }
    
    func handleScroll(delta: CGPoint) {
        logger.debug("handleScroll(delta: CGPoint) called with delta: \(delta)", category: .mouse)
        let deltaX = Int(delta.x)
        let deltaY = Int(delta.y)
        handleScroll(deltaX: deltaX, deltaY: deltaY)
    }
}

// MARK: - Public API
extension MouseInputManager {
    /// Handle tap gesture with timing detection
    func handleTap(at position: CGPoint) {
        logger.debug("handleTap called at position: \(position)", category: .mouse)
        let currentTime = Date().timeIntervalSince1970
        
        logger.debug("Current time: \(currentTime), Last tap time: \(lastTapTime)", category: .mouse)
        logger.debug("Time difference: \(currentTime - lastTapTime)", category: .mouse)
        
        if currentTime - lastTapTime < doubleTapTimeWindow {
            // Double tap detected
            logger.debug("Double tap detected", category: .mouse)
            handleDoubleClick()
        } else {
            // Single tap
            logger.debug("Single tap detected", category: .mouse)
            handleClick()
        }
        
        DispatchQueue.main.async {
            self.lastTapTime = currentTime
        }
    }
    
    /// Handle long press gesture (right click)
    func handleLongPress(at position: CGPoint) {
        logger.debug("handleLongPress called at position: \(position)", category: .mouse)
        // Send right click event
        logger.info("Right click detected - sending right click event", category: .mouse)
        
        // Send right click press
        let mousePressed = 0x02  // Right mouse button
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
    
    /// Handle two-finger tap with direction-based scrolling
    func handleTwoFingerTap(startPosition: CGPoint, endPosition: CGPoint) {
        logger.debug("handleTwoFingerTap called", category: .mouse)
        logger.debug("Start position: \(startPosition)", category: .mouse)
        logger.debug("End position: \(endPosition)", category: .mouse)
        
        let deltaX = endPosition.x - startPosition.x
        let deltaY = endPosition.y - startPosition.y
        
        logger.debug("Raw deltas - X: \(deltaX), Y: \(deltaY)", category: .mouse)
        
        // Determine scroll direction and magnitude
        let scrollDeltaX = Int(deltaX / 10) // Reduce sensitivity
        let scrollDeltaY = Int(deltaY / 10) // Reduce sensitivity
        
        logger.debug("Calculated scroll deltas - X: \(scrollDeltaX), Y: \(scrollDeltaY)", category: .mouse)
        logger.info("Two-finger scroll - deltaX: \(scrollDeltaX), deltaY: \(scrollDeltaY)", category: .mouse)
        handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY)
    }
    
    /// Start two-finger scrolling mode
    func startTwoFingerScrolling() {
        logger.debug("startTwoFingerScrolling called", category: .mouse)
        DispatchQueue.main.async {
            self.isTwoFingerScrolling = true
            self.logger.info("Two-finger scrolling mode: ON", category: .mouse)
        }
    }
    
    /// End two-finger scrolling mode
    func endTwoFingerScrolling() {
        logger.debug("endTwoFingerScrolling called", category: .mouse)
        DispatchQueue.main.async {
            self.isTwoFingerScrolling = false
            self.logger.info("Two-finger scrolling mode: OFF", category: .mouse)
        }
    }
    
    /// Handle continuous two-finger scrolling
    func handleTwoFingerScrolling(currentPosition: CGPoint) {
        logger.debug("handleTwoFingerScrolling called with position: \(currentPosition)", category: .mouse)
        logger.debug("isTwoFingerScrolling state: \(isTwoFingerScrolling)", category: .mouse)
        
        guard isTwoFingerScrolling else { 
            logger.debug("Two-finger scrolling not active, returning", category: .mouse)
            return 
        }
        
        if let previousPos = previousPosition {
            logger.debug("Previous position: \(previousPos)", category: .mouse)
            let deltaX = Int(currentPosition.x - previousPos.x)
            let deltaY = Int(currentPosition.y - previousPos.y)
            
            logger.debug("Raw movement deltas - X: \(deltaX), Y: \(deltaY)", category: .mouse)
            
            // Apply scrolling with reduced sensitivity for smooth scrolling
            let scrollSensitivity = 2
            let scrollDeltaX = deltaX / scrollSensitivity
            let scrollDeltaY = deltaY / scrollSensitivity // Remove double inversion - handleScroll will handle the direction
            
            logger.debug("Scroll deltas after sensitivity - X: \(scrollDeltaX), Y: \(scrollDeltaY)", category: .mouse)
            
            if abs(scrollDeltaX) > 1 || abs(scrollDeltaY) > 1 {
                logger.debug("Calling handleScroll with deltas - X: \(scrollDeltaX), Y: \(scrollDeltaY)", category: .mouse)
                handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY) // Let handleScroll handle the direction
            } else {
                logger.debug("Deltas too small, not scrolling", category: .mouse)
            }
        } else {
            logger.debug("No previous position available", category: .mouse)
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
            self.logger.debug("Drag mode: \(newSelectMode ? "ON" : "OFF")", category: .mouse)
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
        isDragInProgress = false
        dragStartPosition = .zero
        lastProcessedDragPosition = .zero
        internalPreviousPosition = .zero
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
            self.isSelectMode = false
            self.isTwoFingerScrolling = false
            self.lastTapTime = 0
            self.logger.info("Mouse state reset", category: .mouse)
        }
    }
    
    /// Test method to manually trigger a scroll (for debugging)
    func testScroll() {
        logger.debug("Manual test scroll triggered", category: .mouse)
        handleScroll(deltaX: 0, deltaY: 5) // Test scroll down
    }
}
