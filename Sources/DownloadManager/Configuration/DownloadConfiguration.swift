// MARK: - Sources/DownloadManager/Configuration/DownloadConfiguration.swift

import Foundation

// MARK: - Fixed Download Configuration (Sendable)
public struct DownloadConfiguration: Sendable {
    public let downloadsDirectory: URL
    public let maxConcurrentDownloads: Int
    public let allowsCellularAccess: Bool
    public let isDiscretionary: Bool
    public let sessionIdentifier: String
    public let retryLimit: Int
    public let retryDelay: TimeInterval
    public let networkConfiguration: NetworkConfiguration
    
    public init(
        downloadsDirectory: URL? = nil,
        maxConcurrentDownloads: Int = 3,
        allowsCellularAccess: Bool = true,
        isDiscretionary: Bool = false,
        sessionIdentifier: String = "com.app.downloadmanager",
        retryLimit: Int = 3,
        retryDelay: TimeInterval = 2.0
    ) {
        self.downloadsDirectory = downloadsDirectory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads")
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.allowsCellularAccess = allowsCellularAccess
        self.isDiscretionary = isDiscretionary
        self.sessionIdentifier = sessionIdentifier
        self.retryLimit = retryLimit
        self.retryDelay = retryDelay
        self.networkConfiguration = NetworkConfiguration(
            sessionIdentifier: sessionIdentifier,
            allowsCellularAccess: allowsCellularAccess,
            isDiscretionary: isDiscretionary
        )
    }
}

// MARK: - Network Configuration (Sendable)
public struct NetworkConfiguration: Sendable {
    public let sessionIdentifier: String?
    public let allowsCellularAccess: Bool
    public let isDiscretionary: Bool
    
    public init(
        sessionIdentifier: String? = nil,
        allowsCellularAccess: Bool = true,
        isDiscretionary: Bool = false
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.allowsCellularAccess = allowsCellularAccess
        self.isDiscretionary = isDiscretionary
    }
}
