//
//  BluetoothConnectionView.swift
//  Openterface_iOS
//
//  Created by Refactor on 8/3/25.
//

import SwiftUI
import CoreBluetooth

struct BluetoothConnectionView: View {
    @ObservedObject var bluetoothManager: BluetoothConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Connection Status
                if !bluetoothManager.connectedDevices.isEmpty {
                    connectedStatusView
                }
                
                // Bluetooth State Info
                bluetoothStateView
                
                // Device List
                deviceListView
                
                Spacer()
                
                // Control Buttons
                controlButtonsView
            }
            .padding()
            .navigationTitle("Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isScanning ? "Stop" : "Scan") {
                        if isScanning {
                            bluetoothManager.stopScanning()
                        } else {
                            bluetoothManager.startScanning()
                        }
                        isScanning.toggle()
                    }
                    .disabled(!bluetoothManager.connectionState.isReady)
                }
            }
        }
        .onAppear {
            checkScanningState()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Bluetooth Connection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect to Openterface devices")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.top)
    }
    
    // MARK: - Connected Status View
    private var connectedStatusView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected to \(bluetoothManager.connectedDevices.count) device(s)")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            if let rssi = bluetoothManager.qualityMetric {
                SignalStrengthView(rssi: rssi)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Bluetooth State View
    private var bluetoothStateView: some View {
        HStack {
            Image(systemName: bluetoothStateIcon)
                .foregroundColor(bluetoothStateColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Bluetooth Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(bluetoothManager.connectionState.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(bluetoothStateColor)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
    
    // MARK: - Device List View
    private var deviceListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Devices")
                    .font(.headline)
                
                Spacer()
                
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if bluetoothManager.availableDevices.isEmpty {
                emptyDeviceListView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(bluetoothManager.availableDevices, id: \.id) { device in
                            DeviceRowView(
                                device: device,
                                isConnected: bluetoothManager.connectedDevices.contains(device.id),
                                onConnect: {
                                    bluetoothManager.connect(to: device)
                                },
                                onDisconnect: {
                                    bluetoothManager.disconnect(from: device)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    // MARK: - Empty Device List View
    private var emptyDeviceListView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text(emptyDeviceMessage)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
    
    // MARK: - Control Buttons View
    private var controlButtonsView: some View {
        HStack(spacing: 16) {
            if !bluetoothManager.connectionState.isReady {
                Button("Open Bluetooth Settings") {
                    openBluetoothSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button("Refresh") {
                refreshDevices()
            }
            .buttonStyle(.bordered)
            .disabled(!bluetoothManager.connectionState.isReady)
        }
    }
    
    // MARK: - Computed Properties
    private var bluetoothStateIcon: String {
        switch bluetoothManager.connectionState {
        case .poweredOn: return "bluetooth"
        case .poweredOff: return "bluetooth.slash"
        case .unauthorized: return "exclamationmark.triangle"
        default: return "questionmark.circle"
        }
    }
    
    private var bluetoothStateColor: Color {
        switch bluetoothManager.connectionState {
        case .poweredOn: return .green
        case .poweredOff, .unauthorized: return .red
        default: return .orange
        }
    }
    
    private var emptyDeviceMessage: String {
        if !bluetoothManager.connectionState.isReady {
            return "Bluetooth is not available.\nPlease check your settings."
        } else if isScanning {
            return "Scanning for devices...\nMake sure your Openterface device is nearby and discoverable."
        } else {
            return "No devices found.\nTap 'Scan' to search for devices."
        }
    }
    
    // MARK: - Methods
    private func checkScanningState() {
        if bluetoothManager.connectionState.isReady && bluetoothManager.availableDevices.isEmpty {
            bluetoothManager.startScanning()
            isScanning = true
        }
    }
    
    private func refreshDevices() {
        bluetoothManager.stopScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            bluetoothManager.startScanning()
            isScanning = true
        }
    }
    
    private func openBluetoothSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Signal Strength View
struct SignalStrengthView: View {
    let rssi: NSNumber
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: signalIcon)
                .font(.caption2)
                .foregroundColor(signalColor)
            Text("\(rssi.intValue) dBm")
                .font(.caption2)
                .foregroundColor(.gray)
            Text("(\(signalDescription))")
                .font(.caption2)
                .foregroundColor(signalColor)
        }
    }
    
    private var signalIcon: String {
        let value = rssi.intValue
        switch value {
        case -50...0: return "wifi"
        case -70..<(-50): return "wifi"
        case -90..<(-70): return "wifi"
        default: return "wifi.slash"
        }
    }
    
    private var signalColor: Color {
        let value = rssi.intValue
        switch value {
        case -50...0: return .green
        case -70..<(-50): return .orange
        default: return .red
        }
    }
    
    private var signalDescription: String {
        let value = rssi.intValue
        switch value {
        case -50...0: return "Excellent"
        case -70..<(-50): return "Good"
        case -90..<(-70): return "Fair"
        default: return "Poor"
        }
    }
}

// MARK: - Device Row View
struct DeviceRowView: View {
    let device: BluetoothDevice
    let isConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    SignalStrengthView(rssi: device.rssi)
                    
                    if isConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(isConnected ? "Disconnect" : "Connect") {
                if isConnected {
                    onDisconnect()
                } else {
                    onConnect()
                }
            }
            .buttonStyle(.bordered)
            .foregroundColor(isConnected ? .red : .primaryAccent)
        }
        .padding()
        .background(isConnected ? Color.green.opacity(0.1) : Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

#Preview {
    BluetoothConnectionView(bluetoothManager: BluetoothConnectionManager())
}
