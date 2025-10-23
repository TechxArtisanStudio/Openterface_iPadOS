//
//  HIDInputManagerTests.swift
//  Openterface_iOSTests
//
//  Created by Unit Tests on 10/23/25.
//

import XCTest
import CoreGraphics
@testable import Openterface_iOS

/// Unit tests for HIDInputManager
/// Tests both Absolute Mode (Direct Touch) and Relative Mode (Touchpad-style) packet generation
final class HIDInputManagerTests: XCTestCase {
    
    var hidManager: HIDInputManager!
    var mockConnectionManager: MockConnectionManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mockConnectionManager = MockConnectionManager()
        hidManager = HIDInputManager(connectionManager: mockConnectionManager)
    }
    
    override func tearDownWithError() throws {
        hidManager = nil
        mockConnectionManager = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Keyboard Input Tests
    
    func testSendKeyboardInput_NormalMode() throws {
        // Given: Normal keyboard mode with a single key
        let modifier: UInt8 = 0x00
        let keyCodes: [UInt8] = [0x04] // 'A' key
        
        // When: Sending keyboard input
        hidManager.sendKeyboardInput(modifier: modifier, keyCodes: keyCodes, mode: .normal)
        
        // Then: Verify packet structure
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet.count, 14, "Keyboard packet should have 14 bytes")
        XCTAssertEqual(packet[0], 0x57, "Header byte 1 should be 0x57")
        XCTAssertEqual(packet[1], 0xAB, "Header byte 2 should be 0xAB")
        XCTAssertEqual(packet[5], modifier, "Modifier byte should match")
        XCTAssertEqual(packet[6], 0x00, "Reserved byte should be 0x00")
        XCTAssertEqual(packet[7], 0x04, "First key code should be 0x04")
    }
    
    func testSendKeyboardInput_WithModifier() throws {
        // Given: Keyboard input with Ctrl+Shift modifier
        let modifier: UInt8 = 0x03 // Ctrl(0x01) + Shift(0x02)
        let keyCodes: [UInt8] = [0x04, 0x05] // Multiple keys
        
        // When: Sending keyboard input
        hidManager.sendKeyboardInput(modifier: modifier, keyCodes: keyCodes, mode: .normal)
        
        // Then: Verify packet structure
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[5], 0x03, "Modifier should be Ctrl+Shift")
        XCTAssertEqual(packet[7], 0x04, "First key should be 0x04")
        XCTAssertEqual(packet[8], 0x05, "Second key should be 0x05")
    }
    
    func testSendKeyboardInput_MaximumKeys() throws {
        // Given: Maximum 6 keys pressed simultaneously
        let keyCodes: [UInt8] = [0x04, 0x05, 0x06, 0x07, 0x08, 0x09]
        
        // When: Sending keyboard input
        hidManager.sendKeyboardInput(modifier: 0x00, keyCodes: keyCodes, mode: .normal)
        
        // Then: Verify all 6 keys are in packet
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[7], 0x04, "Key 1 should be 0x04")
        XCTAssertEqual(packet[8], 0x05, "Key 2 should be 0x05")
        XCTAssertEqual(packet[9], 0x06, "Key 3 should be 0x06")
        XCTAssertEqual(packet[10], 0x07, "Key 4 should be 0x07")
        XCTAssertEqual(packet[11], 0x08, "Key 5 should be 0x08")
        XCTAssertEqual(packet[12], 0x09, "Key 6 should be 0x09")
    }
    
    // MARK: - Relative Mouse Input Tests (Touchpad-style Mode)
    
    func testSendRelativeMouseInput_Movement() throws {
        // Given: Relative mouse movement
        let deltaX = 10
        let deltaY = -15
        
        // When: Sending relative mouse input
        hidManager.sendRelativeMouseInput(deltaX: deltaX, deltaY: deltaY, buttons: 0x00, wheel: 0)
        
        // Then: Verify packet structure
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet.count, 11, "Relative mouse packet should have 11 bytes")
        XCTAssertEqual(packet[0], 0x57, "Header byte 1")
        XCTAssertEqual(packet[1], 0xAB, "Header byte 2")
        XCTAssertEqual(packet[5], 0x01, "Report ID should be 0x01")
        XCTAssertEqual(packet[6], 0x00, "No buttons pressed")
        XCTAssertEqual(packet[7], 10, "X delta should be 10")
        XCTAssertEqual(packet[8], UInt8(bitPattern: -15), "Y delta should be -15 (two's complement)")
    }
    
    func testSendRelativeMouseInput_WithLeftButton() throws {
        // Given: Relative mouse movement with left button pressed
        let deltaX = 5
        let deltaY = 5
        let buttons: UInt8 = 0x01 // Left button
        
        // When: Sending relative mouse input
        hidManager.sendRelativeMouseInput(deltaX: deltaX, deltaY: deltaY, buttons: buttons, wheel: 0)
        
        // Then: Verify button state
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[6], 0x01, "Left button should be pressed")
    }
    
    func testSendRelativeMouseInput_WithRightButton() throws {
        // Given: Right mouse button click
        let buttons: UInt8 = 0x02 // Right button
        
        // When: Sending relative mouse input
        hidManager.sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: buttons, wheel: 0)
        
        // Then: Verify button state
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[6], 0x02, "Right button should be pressed")
    }
    
    func testSendRelativeMouseInput_WithScroll() throws {
        // Given: Scroll wheel movement
        let wheel = 5 // Scroll up
        
        // When: Sending relative mouse input with scroll
        hidManager.sendRelativeMouseInput(deltaX: 0, deltaY: 0, buttons: 0x00, wheel: wheel)
        
        // Then: Verify wheel value
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[9], 5, "Wheel should scroll up by 5")
    }
    
    func testSendRelativeMouseInput_DeltaClamping() throws {
        // Given: Delta values exceeding limits
        let deltaX = 200 // Exceeds max (127)
        let deltaY = -200 // Exceeds min (-127)
        
        // When: Sending relative mouse input
        hidManager.sendRelativeMouseInput(deltaX: deltaX, deltaY: deltaY, buttons: 0x00, wheel: 0)
        
        // Then: Verify values are clamped
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[7], 127, "X delta should be clamped to 127")
        XCTAssertEqual(packet[8], UInt8(bitPattern: -127), "Y delta should be clamped to -127")
    }
    
    // MARK: - Absolute Mouse Input Tests (Direct Touch Mode)
    
    func testSendAbsoluteMouseInput_CenterPosition() throws {
        // Given: Center position (0.5, 0.5)
        let x: CGFloat = 0.5
        let y: CGFloat = 0.5
        
        // When: Sending absolute mouse input
        hidManager.sendAbsoluteMouseInput(x: x, y: y, buttons: 0x00, wheel: 0)
        
        // Then: Verify packet structure and coordinates
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet.count, 13, "Absolute mouse packet should have 13 bytes")
        XCTAssertEqual(packet[0], 0x57, "Header byte 1")
        XCTAssertEqual(packet[1], 0xAB, "Header byte 2")
        XCTAssertEqual(packet[4], 0x07, "Data length should be 7")
        XCTAssertEqual(packet[5], 0x02, "Report ID should be 0x02")
        
        // Center position should be 2048 (0x800) in 4096×4096 space
        let xCoord = Int(packet[7]) | (Int(packet[8]) << 8)
        let yCoord = Int(packet[9]) | (Int(packet[10]) << 8)
        
        XCTAssertEqual(xCoord, 2048, "X coordinate should be 2048 (center)")
        XCTAssertEqual(yCoord, 2048, "Y coordinate should be 2048 (center)")
    }
    
    func testSendAbsoluteMouseInput_TopLeftCorner() throws {
        // Given: Top-left corner (0.0, 0.0)
        let x: CGFloat = 0.0
        let y: CGFloat = 0.0
        
        // When: Sending absolute mouse input
        hidManager.sendAbsoluteMouseInput(x: x, y: y, buttons: 0x00, wheel: 0)
        
        // Then: Verify coordinates are at origin
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        let xCoord = Int(packet[7]) | (Int(packet[8]) << 8)
        let yCoord = Int(packet[9]) | (Int(packet[10]) << 8)
        
        XCTAssertEqual(xCoord, 0, "X coordinate should be 0")
        XCTAssertEqual(yCoord, 0, "Y coordinate should be 0")
    }
    
    func testSendAbsoluteMouseInput_BottomRightCorner() throws {
        // Given: Bottom-right corner (1.0, 1.0)
        let x: CGFloat = 1.0
        let y: CGFloat = 1.0
        
        // When: Sending absolute mouse input
        hidManager.sendAbsoluteMouseInput(x: x, y: y, buttons: 0x00, wheel: 0)
        
        // Then: Verify coordinates are at max (4095)
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        let xCoord = Int(packet[7]) | (Int(packet[8]) << 8)
        let yCoord = Int(packet[9]) | (Int(packet[10]) << 8)
        
        XCTAssertEqual(xCoord, 4095, "X coordinate should be 4095 (max)")
        XCTAssertEqual(yCoord, 4095, "Y coordinate should be 4095 (max)")
    }
    
    func testSendAbsoluteMouseInput_WithLeftButtonDrag() throws {
        // Given: Absolute position with left button pressed (drag)
        let x: CGFloat = 0.25
        let y: CGFloat = 0.75
        let buttons: UInt8 = 0x01 // Left button
        
        // When: Sending absolute mouse input
        hidManager.sendAbsoluteMouseInput(x: x, y: y, buttons: buttons, wheel: 0)
        
        // Then: Verify button state
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[6], 0x01, "Left button should be pressed")
    }
    
    func testSendAbsoluteMouseInput_WithRightButton() throws {
        // Given: Absolute position with right button
        let buttons: UInt8 = 0x02 // Right button
        
        // When: Sending absolute mouse input
        hidManager.sendAbsoluteMouseInput(x: 0.5, y: 0.5, buttons: buttons, wheel: 0)
        
        // Then: Verify button state
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[6], 0x02, "Right button should be pressed")
    }
    
    func testSendAbsoluteMouseInput_WithScrollUp() throws {
        // Given: Scroll up in absolute mode
        let wheel = 5 // Scroll up
        
        // When: Sending absolute mouse input with scroll
        hidManager.sendAbsoluteMouseInput(x: 0.5, y: 0.5, buttons: 0x00, wheel: wheel)
        
        // Then: Verify wheel byte (0x01-0x7F for scroll up)
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[11], 0x05, "Wheel should be 0x05 (scroll up)")
    }
    
    func testSendAbsoluteMouseInput_WithScrollDown() throws {
        // Given: Scroll down in absolute mode
        let wheel = -5 // Scroll down
        
        // When: Sending absolute mouse input with scroll
        hidManager.sendAbsoluteMouseInput(x: 0.5, y: 0.5, buttons: 0x00, wheel: wheel)
        
        // Then: Verify wheel byte (0x81-0xFF for scroll down)
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[11], 0x85, "Wheel should be 0x85 (0x80 + 5 for scroll down)")
    }
    
    // MARK: - Mouse Click Tests
    
    func testSendMouseClick_LeftButton() throws {
        // Given: Left mouse button click
        let expectation = expectation(description: "Click should send press and release")
        expectation.expectedFulfillmentCount = 2
        
        mockConnectionManager.onSendData = { data in
            expectation.fulfill()
        }
        
        // When: Sending mouse click
        hidManager.sendMouseClick(button: 0x01, releaseDelay: 0.01)
        
        // Then: Wait for both press and release
        wait(for: [expectation], timeout: 0.5)
        XCTAssertEqual(mockConnectionManager.sendCallCount, 2, "Should send press and release")
    }
    
    func testSendMouseDoubleClick() throws {
        // Given: Double click action
        let expectation = expectation(description: "Double click should send 4 packets")
        expectation.expectedFulfillmentCount = 4 // 2 clicks × 2 packets each
        
        mockConnectionManager.onSendData = { data in
            expectation.fulfill()
        }
        
        // When: Sending double click
        hidManager.sendMouseDoubleClick(button: 0x01)
        
        // Then: Wait for all 4 packets
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockConnectionManager.sendCallCount, 4, "Should send 4 packets for double click")
    }
    
    // MARK: - Scroll Input Tests
    
    func testSendScrollInput_VerticalScrollUp() throws {
        // Given: Vertical scroll up
        let deltaY = 10
        
        // When: Sending scroll input
        hidManager.sendScrollInput(deltaX: 0, deltaY: deltaY, sensitivity: 2)
        
        // Then: Verify scroll packet
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[9], 20, "Wheel should be deltaY * sensitivity (10 * 2)")
    }
    
    func testSendScrollInput_VerticalScrollDown() throws {
        // Given: Vertical scroll down
        let deltaY = -10
        
        // When: Sending scroll input
        hidManager.sendScrollInput(deltaX: 0, deltaY: deltaY, sensitivity: 2)
        
        // Then: Verify scroll packet
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        XCTAssertEqual(packet[9], UInt8(bitPattern: -20), "Wheel should be deltaY * sensitivity (-10 * 2)")
    }
    
    // MARK: - Checksum Tests
    
    func testPacketChecksum_Keyboard() throws {
        // Given: Keyboard packet
        hidManager.sendKeyboardInput(modifier: 0x00, keyCodes: [0x04], mode: .normal)
        
        // Then: Verify checksum is correct
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        let checksumIndex = packet.count - 1
        let dataToChecksum = Array(packet[0..<checksumIndex])
        let calculatedChecksum = dataToChecksum.reduce(0 as UInt32) { $0 + UInt32($1) } & 0xFF
        
        XCTAssertEqual(packet[checksumIndex], UInt8(calculatedChecksum), "Checksum should be correct")
    }
    
    func testPacketChecksum_RelativeMouse() throws {
        // Given: Relative mouse packet
        hidManager.sendRelativeMouseInput(deltaX: 10, deltaY: 10, buttons: 0x01, wheel: 0)
        
        // Then: Verify checksum is correct
        let sentData = try XCTUnwrap(mockConnectionManager.lastSentData)
        let packet = [UInt8](sentData)
        
        let checksumIndex = packet.count - 1
        let dataToChecksum = Array(packet[0..<checksumIndex])
        let calculatedChecksum = dataToChecksum.reduce(0 as UInt32) { $0 + UInt32($1) } & 0xFF
        
        XCTAssertEqual(packet[checksumIndex], UInt8(calculatedChecksum), "Checksum should be correct")
    }
}

// MARK: - Mock Connection Manager

class MockConnectionManager: ConnectionProtocol {
    var lastSentData: Data?
    var sendCallCount = 0
    var onSendData: ((Data) -> Void)?
    
    var connectionState: Openterface_iOS.ConnectionState = .disconnected
    var dataTransmission: any Openterface_iOS.DataTransmissionProtocol
    
    init() {
        self.dataTransmission = MockDataTransmission()
        if let mockTransmission = self.dataTransmission as? MockDataTransmission {
            mockTransmission.onSendData = { [weak self] data in
                self?.lastSentData = data
                self?.sendCallCount += 1
                self?.onSendData?(data)
            }
        }
    }
    
    func connect() {}
    func disconnect() {}
}

class MockDataTransmission: DataTransmissionProtocol {
    var onSendData: ((Data) -> Void)?
    
    func sendData(_ data: Data) {
        onSendData?(data)
    }
}
