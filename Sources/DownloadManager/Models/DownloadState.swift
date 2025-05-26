// MARK: - Download State
import Foundation

public enum DownloadState: String, Codable, Equatable {
    case notDownloaded
    case queued
    case downloading
    case paused
    case downloaded
    case failed
    case cancelling // Intermediate state for cancellation
}