// MARK: - Download State
import Foundation

// MARK: - Fixed Download State (Sendable)
public enum DownloadState: String, Codable, Equatable, Sendable {
    case notDownloaded
    case queued
    case downloading
    case paused
    case downloaded
    case failed
    case cancelling // Intermediate state for cancellation
}
