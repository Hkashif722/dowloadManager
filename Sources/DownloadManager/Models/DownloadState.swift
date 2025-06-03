import Foundation

/// Represents the various states of a download operation
enum DownloadState: CaseIterable {
    case notDownloaded
    case queued
    case downloading
    case paused
    case downloaded
    case failed
    case cancelling
    
    /// Whether the download is currently in progress
    var isInProgress: Bool {
        [.downloading, .queued].contains(self)
    }
    
    /// Whether the download can be started or resumed
    var canStart: Bool {
        [.notDownloaded, .failed].contains(self)
    }
    
    /// Whether the download can be paused
    var canPause: Bool {
        self == .downloading
    }
    
    /// Whether the download can be resumed
    var canResume: Bool {
        self == .paused
    }
    
    /// Whether the content is available for playback
    var isPlayable: Bool {
        self == .downloaded
    }
}
