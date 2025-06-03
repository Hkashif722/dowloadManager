import Foundation

/// Represents the various states of a download operation
public enum DownloadState: String, Codable, CaseIterable, Equatable, Sendable {
    case notDownloaded
    case queued
    case downloading
    case paused
    case downloaded
    case failed
    case cancelling
    
    /// Whether the download is currently in progress
    public var isInProgress: Bool {
        [.downloading, .queued].contains(self)
    }
    
    /// Whether the download can be started or resumed
    public var canStart: Bool {
        [.notDownloaded, .failed].contains(self)
    }
    
    /// Whether the download can be paused
    public var canPause: Bool {
        self == .downloading
    }
    
    /// Whether the download can be resumed
    public var canResume: Bool {
        self == .paused
    }
    
    /// Whether the content is available for playback
    public var isPlayable: Bool {
        self == .downloaded
    }
}
