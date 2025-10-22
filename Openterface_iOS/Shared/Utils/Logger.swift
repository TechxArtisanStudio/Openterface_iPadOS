//
//  Logger.swift
//  Openterface_iOS
//
//  Created by Logger System on 10/20/25.
//

import Foundation
import os.log

/// Centralized logging manager for Openterface app
final class Logger {
    // MARK: - Log Levels
    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        
        var prefix: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Log Categories
    enum Category: String {
        case bluetooth = "📶 Bluetooth"
        case camera = "🎬 Camera"
        case input = "⌨️ Input"
        case mouse = "🖱️ Mouse"
        case keyboard = "⌨️ Keyboard"
        case ui = "🖥️ UI"
        case general = "📱 General"
        case network = "🌐 Network"
        case audio = "🔊 Audio"
        
        var icon: String {
            switch self {
            case .bluetooth: return "📶"
            case .camera: return "🎬"
            case .input: return "⌨️"
            case .mouse: return "🖱️"
            case .keyboard: return "⌨️"
            case .ui: return "🖥️"
            case .general: return "📱"
            case .network: return "🌐"
            case .audio: return "🔊"
            }
        }
    }
    
    // MARK: - Configuration
    struct Configuration {
        var isEnabled: Bool = true
        var minimumLevel: LogLevel = .debug
        var enabledCategories: Set<Category> = Set(Category.allCases)
        var useOSLog: Bool = false // Use os.log for better performance in production
        var timestampEnabled: Bool = true // Always enable timestamps
        
        static var `default`: Configuration {
            return Configuration()
        }
        
        #if DEBUG
        static var debug: Configuration {
            return Configuration(
                isEnabled: true,
                minimumLevel: .debug,
                enabledCategories: Set(Category.allCases),
                useOSLog: false,
                timestampEnabled: true
            )
        }
        #else
        static var production: Configuration {
            return Configuration(
                isEnabled: false, // Disable logging in production
                minimumLevel: .error,
                enabledCategories: Set(Category.allCases),
                useOSLog: true,
                timestampEnabled: true // Always enable timestamps
            )
        }
        #endif
    }
    
    // MARK: - Shared Instance
    static let shared = Logger()
    
    // MARK: - Properties
    private var configuration: Configuration
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.openterface.logger", qos: .utility)
    private let osLog = OSLog(subsystem: "com.openterface.app", category: "General")
    
    // MARK: - Initialization
    private init() {
        #if DEBUG
        self.configuration = .debug
        #else
        self.configuration = .production
        #endif
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    // MARK: - Configuration Methods
    func configure(_ config: Configuration) {
        queue.async { [weak self] in
            self?.configuration = config
        }
    }
    
    func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.configuration.isEnabled = enabled
        }
    }
    
    func setMinimumLevel(_ level: LogLevel) {
        queue.async { [weak self] in
            self?.configuration.minimumLevel = level
        }
    }
    
    func enableCategory(_ category: Category) {
        queue.async { [weak self] in
            self?.configuration.enabledCategories.insert(category)
        }
    }
    
    func disableCategory(_ category: Category) {
        queue.async { [weak self] in
            self?.configuration.enabledCategories.remove(category)
        }
    }
    
    func enableAllCategories() {
        queue.async { [weak self] in
            self?.configuration.enabledCategories = Set(Category.allCases)
        }
    }
    
    func disableAllCategories() {
        queue.async { [weak self] in
            self?.configuration.enabledCategories = []
        }
    }
    
    // MARK: - Logging Methods
    func log(_ message: String, level: LogLevel = .info, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if logging is enabled
            guard self.configuration.isEnabled else { return }
            
            // Check log level
            guard level >= self.configuration.minimumLevel else { return }
            
            // Check category
            guard self.configuration.enabledCategories.contains(category) else { return }
            
            // Format message
            let formattedMessage = self.formatMessage(message, level: level, category: category, file: file, function: function, line: line)
            
            // Output
            if self.configuration.useOSLog {
                self.logToOSLog(formattedMessage, level: level)
            } else {
                print(formattedMessage)
            }
        }
    }
    
    // Convenience methods
    func debug(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Formatting
    private func formatMessage(_ message: String, level: LogLevel, category: Category, file: String, function: String, line: Int) -> String {
        var components: [String] = []
        
        // Timestamp
        if configuration.timestampEnabled {
            components.append("[\(dateFormatter.string(from: Date()))]")
        }
        
        // Level
        components.append(level.prefix)
        
        // Category
        components.append("[\(category.rawValue)]")
        
        // Message
        components.append(message)
        
        return components.joined(separator: " ")
    }
    
    private func logToOSLog(_ message: String, level: LogLevel) {
        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", message)
        case .info:
            os_log(.info, log: osLog, "%{public}@", message)
        case .warning:
            os_log(.default, log: osLog, "%{public}@", message)
        case .error:
            os_log(.error, log: osLog, "%{public}@", message)
        }
    }
}

// MARK: - Category CaseIterable
extension Logger.Category: CaseIterable {}

// MARK: - Global Convenience Functions
func logDebug(_ message: String, category: Logger.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.debug(message, category: category, file: file, function: function, line: line)
}

func logInfo(_ message: String, category: Logger.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message, category: category, file: file, function: function, line: line)
}

func logWarning(_ message: String, category: Logger.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message, category: category, file: file, function: function, line: line)
}

func logError(_ message: String, category: Logger.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message, category: category, file: file, function: function, line: line)
}
