// MARK: - Sources/DownloadManager/Utilities/DownloadLogger.swift

import Foundation
import os

/// Logger for download operations
public struct DownloadLogger {
    private static let logger = Logger(subsystem: "com.app.downloadmanager", category: "Downloads")
    
    public static func log(_ message: String, type: OSLogType = .default) {
        logger.log(level: type, "\(message)")
    }
    
    public static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            logger.error("\(message): \(error.localizedDescription)")
        } else {
            logger.error("\(message)")
        }
    }
}