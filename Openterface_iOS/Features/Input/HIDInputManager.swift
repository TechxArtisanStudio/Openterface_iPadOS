//
//  HIDInputManager.swift
//  Openterface_iOS
//
//  Created by Refactor on 10/22/25.
//

import Foundation
import CoreGraphics

/// Generic HID Input Manager that handles all types of HID input packets
/// 
/// This manager abstracts the packet construction and transmission for keyboard, mouse (relative/absolute), and other HID devices.
/// 
/// **Two Control Modes:**
/// 
/// 1. **Absolute Mouse Control** - Touch position on iPad corresponds directly to a point on the PC screen
///    - Good for stylus or precise UI interaction (similar to drawing tablet)
///    - Uses 4096×4096 resolution coordinate space
/// 
/// 2. **Relative Mouse Control** - Touch gestures change mouse movement relative to its current position
///    - Good for touchpad-like behavior (like a laptop trackpad)
///    - Uses delta values (-127 to +127)
final class HIDInputManager {
    private let connectionManager: any ConnectionProtocol
    private let logger = Logger.shared
    
    // MARK: - Mouse Mode
    
    /// Mouse control mode
    enum MouseMode {
        case relative  // Touchpad-style (pan gestures)
        case absolute  // Direct touch/Apple Pencil
    }
    
    private var currentMouseMode: MouseMode = .relative
    private var lastAbsolutePosition: (x: CGFloat, y: CGFloat) = (0.5, 0.5)
    
    // MARK: - Initialization
    init(connectionManager: any ConnectionProtocol) {
        self.connectionManager = connectionManager
        logger.debug("HIDInputManager initialized", category: .input)
    }
    
    // MARK: - Mode Management
    
    /// Set the current mouse control mode
    /// - Parameter mode: The mouse mode to use (.relative for pan/trackpad, .absolute for pencil/direct touch)
    func setMouseMode(_ mode: MouseMode) {
        currentMouseMode = mode
        logger.debug("Mouse mode changed to: \(mode)", category: .input)
    }
    
    /// Get the current mouse mode
    func getMouseMode() -> MouseMode {
        return currentMouseMode
    }
    
    // MARK: - Keyboard Input
    
    /// Send keyboard HID report
    /// - Parameters:
    ///   - modifier: Modifier byte (Ctrl=0x01, Shift=0x02, Alt=0x04, Cmd=0x08)
    ///   - keyCodes: Array of up to 6 key codes
    ///   - mode: Keyboard mode (normal or game)
    func sendKeyboardInput(modifier: UInt8, keyCodes: [UInt8], mode: KeyboardMode = .normal) {
        // HID keyboard report format:
        // [Header (5 bytes), Modifier, Reserved, Key1, Key2, Key3, Key4, Key5, Key6, Checksum]
        var dataPacket: [UInt8] = mode.dataPacketHeader
        dataPacket.append(modifier)
        dataPacket.append(0x00) // Reserved byte
        
        // Add up to 6 key codes, pad with zeros if needed
        let paddedKeyCodes = keyCodes.prefix(6) + Array(repeating: 0x00, count: max(0, 6 - keyCodes.count))
        dataPacket.append(contentsOf: paddedKeyCodes)
        
        // Calculate and append checksum
        let checksum = calculateChecksum(dataPacket)
        dataPacket.append(checksum)
        
        logger.debug("Keyboard: mod=0x\(String(modifier, radix: 16)), keys=\(keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ","))", category: .input)
        sendData(dataPacket)
    }
    
    // MARK: - Mouse Input (Relative Mode)
    
    /// Send relative mouse movement (Touchpad-style mode)
    /// 
    /// **Relative Mode Behaviors:**
    /// - Single tap → Left click
    /// - Tap & drag → Move mouse (relative movement)
    /// - Double tap & hold → Left button drag
    /// - Long press (>0.5s) → Right click
    /// - Two-finger drag → Scroll wheel
    /// 
    /// - Parameters:
    ///   - deltaX: Horizontal movement delta (-127 to 127)
    ///   - deltaY: Vertical movement delta (-127 to 127)
    ///   - buttons: Button state (0x00=none, 0x01=left, 0x02=right, 0x04=middle)
    ///   - wheel: Scroll wheel delta (-127 to 127)
    func sendRelativeMouseInput(deltaX: Int, deltaY: Int, buttons: UInt8 = 0x00, wheel: Int = 0) {
        // HID relative mouse report format:
        // [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, Buttons, X-Delta, Y-Delta, Wheel, Checksum]
        let boundedXDelta = clampToInt8(deltaX)
        let boundedYDelta = clampToInt8(deltaY)
        let boundedWheel = clampToInt8(wheel)
        
        let xByte = toUnsignedByte(boundedXDelta)
        let yByte = toUnsignedByte(boundedYDelta)
        let wheelByte = toUnsignedByte(boundedWheel)
        
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, buttons, xByte, yByte, wheelByte]
        let checksum = calculateChecksum(dataPacket)
        dataPacket.append(checksum)
        
        logger.debug("Relative Mouse: dx=\(deltaX), dy=\(deltaY), btn=0x\(String(buttons, radix: 16))", category: .mouse)
        sendData(dataPacket)
    }
    
    // MARK: - Mouse Input (Absolute Mode)
    
    /// Send absolute mouse position (Direct touch mode)
    /// 
    /// **Absolute Mode Behaviors:**
    /// - Single tap → Move cursor to tapped point + Left click
    /// - Press & hold (>0.3s) → Cursor moves to point + Right click
    /// - Tap & drag → Move cursor + Left button drag
    /// - Double tap → Move cursor + Double-click
    /// - Two-finger tap → Right click
    /// - Two-finger drag (up/down) → Scroll wheel
    /// 
    /// - Parameters:
    ///   - x: Absolute X coordinate (0.0 to 1.0, normalized screen position)
    ///   - y: Absolute Y coordinate (0.0 to 1.0, normalized screen position)
    ///   - buttons: Button state (Bit0=left, Bit1=right, Bit2=middle)
    ///   - wheel: Scroll wheel delta (0x01-0x7F=up, 0x81-0xFF=down, 0x00=no scroll)
    func sendAbsoluteMouseInput(x: CGFloat, y: CGFloat, buttons: UInt8 = 0x00, wheel: Int = 0) {
        // Store position for future click operations
        lastAbsolutePosition = (x, y)
        
        // HID absolute mouse report format (CMD_SEND_MS_ABS_DATA):
        // [0x57, 0xAB, 0x00, 0x04, 0x07, 0x02, Buttons, X-Low, X-High, Y-Low, Y-High, Wheel, Checksum]
        // 
        // IMPORTANT: The chip simulates an absolute mouse with 4096×4096 resolution
        // The peripheral device must calculate coordinates based on its screen resolution:
        //   X_Cur = (4096 * X_pixel) / X_MAX_screen
        //   Y_Cur = (4096 * Y_pixel) / Y_MAX_screen
        //
        // Data bytes (7 bytes total):
        // Byte 1: Must be 0x02
        // Byte 2: Button state (Bit2-Bit0: 1=pressed, 0=released)
        //         Bit0=Left, Bit1=Right, Bit2=Middle
        // Byte 3-4: X coordinate (16-bit, low byte first, high byte second, range: 0-4095)
        // Byte 5-6: Y coordinate (16-bit, low byte first, high byte second, range: 0-4095)
        // Byte 7: Wheel scroll
        //         0x00 = no scroll
        //         0x01-0x7F = scroll up (units: ticks)
        //         0x81-0xFF = scroll down (units: ticks)
        
        // Convert normalized coordinates (0.0-1.0) to absolute HID coordinates (0-4095)
        // The chip uses 4096×4096 resolution for absolute mouse
        let absoluteX = Int(x * 4096.0)
        let absoluteY = Int(y * 4096.0)
        
        // Clamp to valid range (0-4095)
        let clampedX = max(0, min(4095, absoluteX))
        let clampedY = max(0, min(4095, absoluteY))
        
        // Split into low and high bytes (16-bit coordinates, little-endian)
        let xLow = UInt8(clampedX & 0xFF)
        let xHigh = UInt8((clampedX >> 8) & 0xFF)
        let yLow = UInt8(clampedY & 0xFF)
        let yHigh = UInt8((clampedY >> 8) & 0xFF)
        
        // Convert wheel delta to protocol format
        let wheelByte = toWheelByte(wheel)
        
        // Only use lower 3 bits for button state (Bit0=Left, Bit1=Right, Bit2=Middle)
        let buttonByte = buttons & 0x07
        
        // Construct packet: Header + 0x02 (required) + buttons + coordinates + wheel
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x04, 0x07, 0x02, buttonByte, xLow, xHigh, yLow, yHigh, wheelByte]
        let checksum = calculateChecksum(dataPacket)
        dataPacket.append(checksum)
        
        logger.debug("Absolute Mouse: norm(\(x), \(y)) -> abs(\(clampedX), \(clampedY)) [0x\(String(clampedX, radix: 16)), 0x\(String(clampedY, radix: 16))], btn=0x\(String(buttonByte, radix: 16)), wheel=0x\(String(wheelByte, radix: 16))", category: .mouse)
        sendData(dataPacket)
    }
    
    // MARK: - Mouse Scroll
    
    /// Send mouse scroll event
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta
    ///   - deltaY: Vertical scroll delta
    ///   - sensitivity: Scroll sensitivity multiplier
    func sendScrollInput(deltaX: Int, deltaY: Int, sensitivity: Int = 2) {
        // Vertical scrolling
        if deltaY != 0 {
            let adjustedDeltaY = deltaY * sensitivity
            sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: 0x00, wheel: adjustedDeltaY)
        }
        
        // Horizontal scrolling (if supported)
        if deltaX != 0 {
            let adjustedDeltaX = deltaX * sensitivity
            let boundedDeltaX = clampToInt8(adjustedDeltaX)
            let xByte = toUnsignedByte(boundedDeltaX)
            
            var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, xByte, 0x00, 0x00]
            let checksum = calculateChecksum(dataPacket)
            dataPacket.append(checksum)
            
            sendData(dataPacket)
        }
    }
    
    // MARK: - Mouse Buttons
    
    /// Send mouse click (press and release) - respects current mode
    /// - Parameters:
    ///   - button: Button to click (0x01=left, 0x02=right, 0x04=middle)
    ///   - releaseDelay: Delay before releasing the button (in seconds)
    ///   - position: Optional position for absolute mode (uses last position if nil)
    func sendMouseClick(button: UInt8 = 0x01, releaseDelay: TimeInterval = 0.05, position: (x: CGFloat, y: CGFloat)? = nil) {
        switch currentMouseMode {
        case .relative:
            // Press
            sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: button, wheel: 0)
            
            // Release after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay) {
                self.sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: 0x00, wheel: 0)
            }
            
        case .absolute:
            let pos = position ?? lastAbsolutePosition
            // Press
            sendAbsoluteMouseInput(x: pos.x, y: pos.y, buttons: button, wheel: 0)
            
            // Release after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay) {
                self.sendAbsoluteMouseInput(x: pos.x, y: pos.y, buttons: 0x00, wheel: 0)
            }
        }
    }
    
    /// Send double click - respects current mode
    /// - Parameters:
    ///   - button: Button to double click (0x01=left, 0x02=right, 0x04=middle)
    ///   - position: Optional position for absolute mode (uses last position if nil)
    func sendMouseDoubleClick(button: UInt8 = 0x01, position: (x: CGFloat, y: CGFloat)? = nil) {
        // First click
        sendMouseClick(button: button, releaseDelay: 0.05, position: position)
        
        // Second click after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendMouseClick(button: button, releaseDelay: 0.05, position: position)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate checksum for HID packet
    private func calculateChecksum(_ packet: [UInt8]) -> UInt8 {
        let sum = packet.reduce(0 as UInt32) { $0 + UInt32($1) }
        return UInt8(sum & 0xFF)
    }
    
    /// Clamp integer value to signed 8-bit range (-127 to 127)
    private func clampToInt8(_ value: Int) -> Int {
        return max(-127, min(127, value))
    }
    
    /// Convert signed integer to unsigned byte (two's complement)
    private func toUnsignedByte(_ value: Int) -> UInt8 {
        return value >= 0 ? UInt8(value) : UInt8(0x100 + value)
    }
    
    /// Convert wheel delta to protocol format
    /// - Parameter delta: Positive=scroll up, Negative=scroll down, 0=no scroll
    /// - Returns: Protocol wheel byte (0x00=none, 0x01-0x7F=up, 0x81-0xFF=down)
    private func toWheelByte(_ delta: Int) -> UInt8 {
        if delta == 0 {
            return 0x00
        } else if delta > 0 {
            // Scroll up: 0x01 to 0x7F (max 127 ticks)
            return UInt8(min(delta, 0x7F))
        } else {
            // Scroll down: 0x81 to 0xFF (max 127 ticks down)
            let absDelta = abs(delta)
            return UInt8(min(0x80 + absDelta, 0xFF))
        }
    }
    
    /// Send data packet via connection manager
    private func sendData(_ packet: [UInt8]) {
        let data = Data(packet)
        connectionManager.dataTransmission.sendData(data)
        
        // Log packet in debug mode
        #if DEBUG
        let hexString = packet.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        logger.debug("HID Packet: \(hexString)", category: .input)
        #endif
    }
}

// MARK: - Button Constants
extension HIDInputManager {
    enum MouseButton: UInt8 {
        case none = 0x00
        case left = 0x01
        case right = 0x02
        case middle = 0x04
    }
    
    enum ModifierKey: UInt8 {
        case leftControl = 0x01
        case leftShift = 0x02
        case leftAlt = 0x04
        case leftCommand = 0x08
        case rightControl = 0x10
        case rightShift = 0x20
        case rightAlt = 0x40
        case rightCommand = 0x80
    }
}
