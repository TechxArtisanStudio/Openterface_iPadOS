//
//  MouseInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import Foundation
import CoreGraphics

/// Mouse Input Manager supporting two control modes:
/// 
/// **1. Absolute Mode (Direct Touch)** - Touch position corresponds directly to PC cursor position
/// **2. Relative Mode (Touchpad-style)** - Touch gestures move cursor relative to current position
final class MouseInputManager: ObservableObject {
    private let logger = Logger.shared
    
    // MARK: - Gesture Recognition Constants
    
    /// Movement threshold to distinguish between click and drag (in pixels)
    private let movementThreshold: CGFloat = 5.0
    
    /// Touch duration thresholds (in seconds)
    private struct TouchDuration {
        static let tap: TimeInterval = 0.2          // < 200ms = Tap/Click
        static let longPress: TimeInterval = 0.3    // > 300ms = Long press (Right click in absolute mode)
        static let dragStart: TimeInterval = 0.5    // > 500ms = Drag start (in relative mode)
    }
    
    /// Multi-tap timing windows
    private struct TapWindow {
        static let relativeMode: TimeInterval = 0.3  // For relative mode double-tap detection
        static let absoluteMode: TimeInterval = 0.2  // For absolute mode multi-tap detection
    }
    
    // MARK: - Published Properties
    @Published var currentPosition: CGPoint? = nil
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false // Track drag mode state
    @Published var isTwoFingerScrolling: Bool = false // Track two-finger scroll state
    @Published var isAbsoluteMode: Bool = false // false = Relative mode (touchpad), true = Absolute mode (direct touch)
    
    // MARK: - Private Properties
    private let connectionManager: any ConnectionProtocol
    private let hidInputManager: HIDInputManager
    
    // Tap tracking
    private var lastTapTime: TimeInterval = 0
    private var lastTapPosition: CGPoint = .zero
    private var tapCount: Int = 0
    
    // Touch timing
    private var touchStartTime: TimeInterval = 0
    private var touchStartPosition: CGPoint = .zero
    
    // Drag tracking
    private var dragStartPosition: CGPoint = .zero
    private var isDragInProgress: Bool = false
    private var lastProcessedDragPosition: CGPoint = .zero  // For deduplication
    private var internalPreviousPosition: CGPoint = .zero  // For synchronous delta calculation
    private let dragQueue = DispatchQueue(label: "com.openterface.mouse.drag", qos: .userInteractive)
    
    // View bounds for coordinate normalization
    private var viewBounds: CGRect = .zero
    private var videoRect: CGRect = .zero
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
        self.hidInputManager = HIDInputManager(connectionManager: connectionManager)
        logger.debug("MouseInputManager initialized", category: .mouse)
    }
    
    // MARK: - Mode Control
    
    /// Set mouse control mode
    /// 
    /// **Absolute Mode (enabled = true):**
    /// - Single tap → Move cursor + Left click
    /// - Press & hold (>0.3s) → Right click
    /// - Tap & drag → Move cursor + Left button drag
    /// - Double tap → Double-click
    /// 
    /// **Relative Mode (enabled = false):**
    /// - Single tap → Left click
    /// - Tap & drag → Move mouse (relative movement)
    /// - Double tap & hold → Left button drag
    /// - Long press (>0.5s) → Right click
    /// 
    /// - Parameter enabled: true for absolute mode, false for relative mode
    func setAbsoluteMode(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.isAbsoluteMode = enabled
            self.logger.debug("Mouse mode set to: \(enabled ? "Absolute (Direct Touch)" : "Relative (Touchpad)")", category: .mouse)
        }
    }
    
    /// Update view bounds for absolute mode coordinate normalization
    /// - Parameter bounds: The bounds of the view where mouse gestures occur
    func updateViewBounds(_ bounds: CGRect) {
        viewBounds = bounds
        logger.debug("View bounds updated: \(bounds)", category: .mouse)
    }
    
    /// Update video rect for absolute mode coordinate normalization
    /// - Parameter rect: The rect of the video content within the view
    func updateVideoRect(_ rect: CGRect) {
        videoRect = rect
        logger.debug("Video rect updated: \(rect)", category: .mouse)
    }
    
    // MARK: - Helper Methods
    
    /// Check if movement exceeds threshold to distinguish click from drag
    /// - Parameters:
    ///   - from: Starting position
    ///   - to: Current position
    /// - Returns: true if movement exceeds threshold
    private func exceedsMovementThreshold(from: CGPoint, to: CGPoint) -> Bool {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance > movementThreshold
    }
    
    /// Get current time for gesture timing
    private func currentTime() -> TimeInterval {
        return Date().timeIntervalSince1970
    }
    
    /// Send mouse button state using the appropriate mode (absolute or relative)
    /// - Parameters:
    ///   - buttons: Button state (0x00=none, 0x01=left, 0x02=right, 0x04=middle)
    ///   - position: Optional position for absolute mode (if nil, uses currentPosition or center)
    ///   - wheel: Scroll wheel delta
    private func sendMouseButtonState(buttons: UInt8, position: CGPoint? = nil, wheel: Int = 0) {
        if isAbsoluteMode {
            // Absolute mode: send position along with button state
            let posToUse = position ?? currentPosition ?? CGPoint(x: viewBounds.width / 2, y: viewBounds.height / 2)
            var normalizedX: CGFloat = 0.5
            var normalizedY: CGFloat = 0.5
            
            if viewBounds.width > 0 && viewBounds.height > 0 {
                normalizedX = max(0.0, min(1.0, posToUse.x / viewBounds.width))
                normalizedY = max(0.0, min(1.0, posToUse.y / viewBounds.height))
            }
            
            hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: buttons, wheel: wheel)
        } else {
            // Relative mode: send zero delta with button state
            hidInputManager.sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: buttons, wheel: wheel)
        }
    }
    
    // MARK: - Drag Event Handlers
    func handleDragChanged(currentPosition: CGPoint) {
        if isAbsoluteMode {
            handleAbsoluteMode(currentPosition: currentPosition)
        } else {
            handleRelativeMode(currentPosition: currentPosition)
        }
    }
    
    private func handleRelativeMode(currentPosition: CGPoint) {
        var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
        var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
        
        // Update both positions on main thread to avoid UI update issues
        DispatchQueue.main.async {
            self.currentPosition = currentPosition
            self.previousPosition = currentPosition
        }
        
        let mouseButtons: UInt8 = isSelectMode ? 0x01 : 0x00
        xDelta *= 4
        yDelta *= 4
        
        // Use HIDInputManager for sending relative mouse data
        hidInputManager.sendRelativeMouseInput(deltaX: xDelta, deltaY: yDelta, buttons: mouseButtons, wheel: 0)
    }
    
    private func handleAbsoluteMode(currentPosition: CGPoint) {
        // Update positions on main thread to avoid UI update issues
        DispatchQueue.main.async {
            self.currentPosition = currentPosition
            self.previousPosition = currentPosition
        }
        
        // In iPencil mode, drag sends left mouse button pressed (0x01) to enable dragging/selection
        // This allows dragging windows, selecting text, etc.
        let mouseButtons: UInt8 = isDragInProgress ? 0x01 : 0x00
        
        logger.debug("handleAbsoluteMode: isDragInProgress=\(isDragInProgress), buttons=\(mouseButtons)", category: .mouse)
        
        // Normalize coordinates from view pixel space to 0.0-1.0 range
        var normalizedX: CGFloat = 0.5
        var normalizedY: CGFloat = 0.5
        
        if videoRect.width > 0 && videoRect.height > 0 {
            // Normalize based on video rect
            normalizedX = max(0.0, min(1.0, (currentPosition.x - videoRect.origin.x) / videoRect.width))
            normalizedY = max(0.0, min(1.0, (currentPosition.y - videoRect.origin.y) / videoRect.height))
            logger.debug("Using video rect: \(videoRect), Normalized coords: pixel(\(currentPosition.x), \(currentPosition.y)) -> norm(\(normalizedX), \(normalizedY)), buttons: \(mouseButtons)", category: .mouse)
        } else if viewBounds.width > 0 && viewBounds.height > 0 {
            // Fallback to view bounds
            normalizedX = max(0.0, min(1.0, currentPosition.x / viewBounds.width))
            normalizedY = max(0.0, min(1.0, currentPosition.y / viewBounds.height))
            logger.debug("Using view bounds: \(viewBounds), Normalized coords: pixel(\(currentPosition.x), \(currentPosition.y)) -> norm(\(normalizedX), \(normalizedY)), buttons: \(mouseButtons)", category: .mouse)
        } else {
            logger.warning("Neither video rect nor view bounds set for absolute mode, using center position", category: .mouse)
        }
        
        // Use HIDInputManager for sending absolute mouse data
        // Send button state based on drag progress: 0x01 during drag, 0x00 otherwise
        hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: mouseButtons, wheel: 0)
    }

    func handleDragEnded(at finalPosition: CGPoint? = nil) {
        logger.debug("handleDragEnded called - isAbsoluteMode: \(isAbsoluteMode), isDragInProgress: \(isDragInProgress)", category: .mouse)
        
        // In absolute mode, send proper drag end sequence
        // Use provided finalPosition, or fall back to currentPosition
        let endPosition = finalPosition ?? currentPosition
        
        if isAbsoluteMode, let position = endPosition {
            logger.debug("iPencil mode: Ending drag at position: \(position)", category: .mouse)
            var normalizedX: CGFloat = 0.5
            var normalizedY: CGFloat = 0.5
            
            if viewBounds.width > 0 && viewBounds.height > 0 {
                normalizedX = max(0.0, min(1.0, position.x / viewBounds.width))
                normalizedY = max(0.0, min(1.0, position.y / viewBounds.height))
            }
            
            // CRITICAL: Send final position with button STILL PRESSED (0x01) first
            // Some systems need to see the pressed state at the final position before the release
            hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x01, wheel: 0)
            logger.debug("iPencil mode: Sent final drag position with button pressed (0x01)", category: .mouse)
            
            // Longer delay to ensure the target device processes the pressed state
            // Some systems need more time between button state changes
            Thread.sleep(forTimeInterval: 0.010) // 10ms delay (increased from 1ms)
            
            // Now send button release at the same position
            hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
            logger.debug("iPencil mode: Sent button release (0x00) at final position", category: .mouse)
            
            // Additional delay after release to ensure it's processed before next gesture
            Thread.sleep(forTimeInterval: 0.010) // 10ms delay
            logger.debug("iPencil mode: Drag end sequence complete", category: .mouse)
        } else {
            // Relative mode: send button release
            logger.debug("Relative mode: Sending button release", category: .mouse)
            sendMouseButtonState(buttons: 0x00, wheel: 0)
        }
        
        // Reset drag state AFTER sending the release sequence
        isDragInProgress = false
        logger.debug("Drag state reset - isDragInProgress now: false", category: .mouse)
        
        // Reset all tracking state
        dragStartPosition = .zero  // Reset for next drag
        lastProcessedDragPosition = .zero  // Reset deduplication state
        internalPreviousPosition = .zero  // Reset internal tracking
        DispatchQueue.main.async {
            self.currentPosition = nil
            self.previousPosition = nil
            self.isSelectMode = false
        }
    }

    func handleDoubleClick() {
        logger.debug("Performing double click action", category: .mouse)
        
        // Use HIDInputManager for double click
        hidInputManager.sendMouseDoubleClick(button: 0x01)
    }
    
    func handleDragModeToggle() {
        let newSelectMode = !isSelectMode
        DispatchQueue.main.async {
            self.isSelectMode = newSelectMode
            self.logger.debug("Drag mode: \(newSelectMode ? "ON" : "OFF")", category: .mouse)
        }
        
        // Use helper method to send mouse state with mode awareness
        let mouseState: UInt8 = newSelectMode ? 0x01 : 0x00
        sendMouseButtonState(buttons: mouseState, wheel: 0)
    }

    func enterDraggingMode() {
        DispatchQueue.main.async {
            self.isSelectMode = true
            self.logger.debug("Entered dragging mode", category: .mouse)
        }
        
        // Use helper method to send mouse press with mode awareness
        sendMouseButtonState(buttons: 0x01, wheel: 0)
    }

    func exitDraggingMode() {
        DispatchQueue.main.async {
            self.isSelectMode = false
            self.logger.debug("Exited dragging mode", category: .mouse)
        }
        
        // Use helper method to send mouse release with mode awareness
        sendMouseButtonState(buttons: 0x00, wheel: 0)
    }

    func handleRightClick() {
        logger.debug("Performing right click action", category: .mouse)
        
        // Use HIDInputManager for right click
        hidInputManager.sendMouseClick(button: 0x02)
    }

    func handleClick() {
        logger.debug("Performing click action", category: .mouse)
        
        // Use HIDInputManager for click
        hidInputManager.sendMouseClick(button: 0x01)
    }

    func handleScroll(deltaX: Int, deltaY: Int) {
        logger.debug("handleScroll called with deltaX: \(deltaX), deltaY: \(deltaY)", category: .mouse)
        
        // Use HIDInputManager for scrolling with sensitivity adjustment
        hidInputManager.sendScrollInput(deltaX: deltaX, deltaY: deltaY, sensitivity: 2)
    }
}

// MARK: - MouseInputProtocol Conformance
extension MouseInputManager: MouseInputProtocol {
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
            // Use helper method to send mouse press with mode awareness
            sendMouseButtonState(buttons: 0x01, wheel: 0)
        case (.left, .release):
            DispatchQueue.main.async {
                self.isSelectMode = false
            }
            // Use helper method to send mouse release with mode awareness
            sendMouseButtonState(buttons: 0x00, wheel: 0)
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
    
    /// Handle drag gesture with movement threshold and mode-specific behavior
    /// 
    /// **Absolute Mode:** Tap & drag → Move cursor + Left button drag
    /// **Relative Mode:** 
    /// - Tap & drag → Move mouse (relative movement)
    /// - Double tap & hold → Left button drag
    /// 
    /// Uses movement threshold (5px) to distinguish between click and drag
    func handleDragGesture(start: CGPoint, current: CGPoint, end: CGPoint?) {
        // Use serial queue to prevent race conditions from duplicate gesture calls
        dragQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.debug("handleDragGesture called - start: \(start), current: \(current), end: \(String(describing: end)), isDragInProgress: \(self.isDragInProgress), mode: \(self.isAbsoluteMode ? "Absolute" : "Relative")", category: .mouse)
            
            // Handle drag end
            if let endPosition = end {
                self.logger.debug("Drag ended detected - calling handleDragEnded() with final position: \(endPosition)", category: .mouse)
                self.handleDragEnded(at: endPosition)
                return  // Exit early after handling drag end
            }
            
            // Handle ongoing drag
            // On the first call of a new drag (when isDragInProgress is false), initialize it
            if !self.isDragInProgress {
                self.dragStartPosition = start
                self.lastProcessedDragPosition = start
                self.internalPreviousPosition = start  // Initialize internal tracking
                
                // CRITICAL: Set isDragInProgress = true BEFORE calling handleDragChanged
                // so that handleAbsoluteMode will send button 0x01 (pressed)
                self.isDragInProgress = true
                
                DispatchQueue.main.async {
                    self.currentPosition = start
                    self.previousPosition = start
                }
                self.logger.debug("First drag - initialized positions to start: \(start), isDragInProgress: true", category: .mouse)
                
                // In absolute mode, send initial position with button press
                // isDragInProgress is now true, so button will be 0x01
                if self.isAbsoluteMode {
                    self.handleDragChanged(currentPosition: start)
                    self.logger.debug("Sent initial drag position with button pressed", category: .mouse)
                    // Don't return early - allow the first position to be set as lastProcessedDragPosition
                } else {
                    // Relative mode: return early to skip delta calculation on first drag
                    return
                }
            }
            
            // Deduplication: Skip if this is the same position as the last processed drag
            // BUT: In absolute mode (iPencil), we need every position update for smooth drawing
            // Only deduplicate in relative mode where duplicate events can cause jitter
            if !self.isAbsoluteMode && current == self.lastProcessedDragPosition {
                self.logger.debug("Skipping duplicate drag gesture at position: \(current) (relative mode only)", category: .mouse)
                return
            }
            
            // Update last processed position for deduplication (relative mode only)
            if !self.isAbsoluteMode {
                self.lastProcessedDragPosition = current
            }
            
            // Update published properties on main thread for UI updates
            DispatchQueue.main.async {
                self.currentPosition = current
                self.previousPosition = current
            }
            
            // Route to appropriate mode handler
            if self.isAbsoluteMode {
                // Absolute mode: send absolute position with button state
                self.handleDragChanged(currentPosition: current)
            } else {
                // Relative mode: calculate and send delta
                let xDelta = Int(current.x - self.internalPreviousPosition.x)
                let yDelta = Int(current.y - self.internalPreviousPosition.y)
                
                self.logger.debug("Calculated incremental deltas - xDelta: \(xDelta), yDelta: \(yDelta)", category: .mouse)
                
                // Update internal tracking position for next delta calculation
                self.internalPreviousPosition = current
                
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
/// 
/// Gesture Mapping Summary:
/// 
/// **Absolute Mode (Direct Touch):**
/// - Single tap → Move cursor to tapped point + Left click
/// - Press & hold (>0.3s) → Cursor moves to point + Right click
/// - Tap & drag → Move cursor + Left button drag
/// - Double tap → Move cursor + Double-click
/// - Two-finger tap → Right click
/// - Two-finger drag (up/down) → Scroll wheel
/// 
/// **Relative Mode (Touchpad-style):**
/// - Single tap → Left click
/// - Tap & drag → Move mouse (relative movement)
/// - Double tap & hold → Left button drag
/// - Double tap → Double-click
/// - Long press (>0.5s) → Right click
/// - Two-finger tap → Right click
/// - Two-finger drag (vertical/horizontal) → Scroll wheel
extension MouseInputManager {
    /// Handle tap gesture with timing detection
    /// 
    /// **Absolute Mode:**
    /// - Single tap → Move cursor to tapped point + Left click
    /// - Double tap → Move cursor + Double-click
    /// 
    /// **Relative Mode:**
    /// - Single tap → Left click
    /// - Double tap → Double-click
    func handleTap(at position: CGPoint) {
        logger.debug("handleTap called at position: \(position), mode: \(isAbsoluteMode ? "Absolute" : "Relative")", category: .mouse)
        let now = currentTime()
        let timeSinceLastTap = now - lastTapTime
        
        if isAbsoluteMode {
            // Absolute mode: Move cursor immediately, then detect multi-taps for click actions
            logger.debug("Absolute mode: Moving cursor immediately to position", category: .mouse)
            moveMouseToPosition(position)
            
            // Detect multi-tap for click actions (using shorter window for absolute mode)
            if timeSinceLastTap < TapWindow.absoluteMode {
                tapCount += 1
                logger.debug("Incremented tap count to: \(tapCount)", category: .mouse)
                
                // Cancel previous delayed action if any
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                
                // Wait to see if another tap comes
                if tapCount == 2 {
                    let capturedTime = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + TapWindow.absoluteMode) { [weak self] in
                        guard let self = self else { return }
                        // If still at 2 taps after waiting, perform single click
                        if self.tapCount == 2 && abs(capturedTime - self.lastTapTime) < 0.01 {
                            self.logger.debug("Absolute mode: Double tap confirmed - clicking at position", category: .mouse)
                            self.clickAtPosition(position)
                            self.tapCount = 0
                        }
                    }
                } else if tapCount >= 3 {
                    // Triple tap = double click (execute immediately)
                    logger.debug("Absolute mode: Triple tap - double clicking at position", category: .mouse)
                    doubleClickAtPosition(position)
                    tapCount = 0
                }
            } else {
                // Timeout - reset tap count
                tapCount = 1
                logger.debug("Reset tap count to 1 (timeout)", category: .mouse)
            }
            
            DispatchQueue.main.async {
                self.lastTapTime = now
                self.lastTapPosition = position
            }
        } else {
            // Relative mode: tap = click, double tap = double click
            if timeSinceLastTap < TapWindow.relativeMode {
                // Double tap detected
                logger.debug("Relative mode: Double tap detected", category: .mouse)
                handleDoubleClick()
                tapCount = 0
            } else {
                // Single tap
                logger.debug("Relative mode: Single tap detected", category: .mouse)
                handleClick()
                tapCount = 1
            }
            
            DispatchQueue.main.async {
                self.lastTapTime = now
                self.lastTapPosition = position
            }
        }
    }
    
    /// Move mouse cursor to absolute position (iPencil mode only)
    private func moveMouseToPosition(_ position: CGPoint) {
        var normalizedX: CGFloat = 0.5
        var normalizedY: CGFloat = 0.5
        
        if viewBounds.width > 0 && viewBounds.height > 0 {
            normalizedX = max(0.0, min(1.0, position.x / viewBounds.width))
            normalizedY = max(0.0, min(1.0, position.y / viewBounds.height))
        }
        
        hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
    }
    
    /// Click at absolute position (iPencil mode only)
    private func clickAtPosition(_ position: CGPoint) {
        var normalizedX: CGFloat = 0.5
        var normalizedY: CGFloat = 0.5
        
        if viewBounds.width > 0 && viewBounds.height > 0 {
            normalizedX = max(0.0, min(1.0, position.x / viewBounds.width))
            normalizedY = max(0.0, min(1.0, position.y / viewBounds.height))
        }
        
        // Move to position, press, release
        hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x01, wheel: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
            }
        }
    }
    
    /// Double click at absolute position (iPencil mode only)
    private func doubleClickAtPosition(_ position: CGPoint) {
        var normalizedX: CGFloat = 0.5
        var normalizedY: CGFloat = 0.5
        
        if viewBounds.width > 0 && viewBounds.height > 0 {
            normalizedX = max(0.0, min(1.0, position.x / viewBounds.width))
            normalizedY = max(0.0, min(1.0, position.y / viewBounds.height))
        }
        
        // Move to position
        hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
        
        // First click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x01, wheel: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
                
                // Second click
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x01, wheel: 0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.hidInputManager.sendAbsoluteMouseInput(x: normalizedX, y: normalizedY, buttons: 0x00, wheel: 0)
                    }
                }
            }
        }
    }
    
    /// Handle long press gesture (right click)
    /// 
    /// **Absolute Mode:** Press & hold (>0.3s) → Cursor moves to point + Right click
    /// **Relative Mode:** Long press (>0.5s) → Right click
    func handleLongPress(at position: CGPoint) {
        logger.debug("handleLongPress called at position: \(position), mode: \(isAbsoluteMode ? "Absolute" : "Relative")", category: .mouse)
        
        // In absolute mode, move cursor to position first
        if isAbsoluteMode {
            moveMouseToPosition(position)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.handleRightClick()
            }
        } else {
            // In relative mode, just right click at current position
            handleRightClick()
        }
        
        logger.info("Right click detected - sending right click event", category: .mouse)
    }
    
    func handleLeftClick(at position: CGPoint) {
        logger.debug("handleLeftClick called at position: \(position), mode: \(isAbsoluteMode ? "Absolute" : "Relative")", category: .mouse)
        
        // In absolute mode, move cursor to position first
        if isAbsoluteMode {
            moveMouseToPosition(position)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.handleClick()
            }
        } else {
            // In relative mode, just left click at current position
            handleClick()
        }
        
        logger.info("Left click detected - sending left click event", category: .mouse)
    }
    
    /// Handle two-finger tap with direction-based scrolling
    /// 
    /// **Both Modes:** Two-finger drag (vertical/horizontal) → Scroll wheel
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
