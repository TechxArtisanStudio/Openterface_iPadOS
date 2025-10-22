//
//  Openterface_iOSApp.swift
//  Openterface_iOS
//
//  Created by 彭志坚 on 8/2/25.
//

import SwiftUI

@main
struct Openterface_iOSApp: App {
    
    // init() {
    //     // Configure logging
    //     // Disable Bluetooth logging to reduce console noise
    //     // Logger.shared.disableCategory(.bluetooth)
        
    //     // Alternative options:
    //     // Logger.shared.setEnabled(false)  // Disable ALL logging
    //     // Logger.shared.setMinimumLevel(.warning)  // Only show warnings and errors
    //     // Logger.shared.disableCategory(.mouse)  // Disable mouse logs too
    // }
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
        }
    }
}
