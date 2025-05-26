// MARK: - Download Type Protocol
import Foundation

/// Defines the types of downloads supported
public protocol DownloadTypeProtocol: RawRepresentable, CaseIterable, Sendable, Hashable, Codable where RawValue == String {
    var fileExtension: String { get }
    var mimeType: String? { get }
    var requiresSpecialHandling: Bool { get }
}
