// MARK: - Download Progress
import Foundation

// MARK: - Fixed Download Progress Data (Sendable)
public struct DownloadProgressData: Codable, Equatable, Sendable {
    public let itemId: UUID
    public let bytesWritten: Int64
    public let totalBytesExpected: Int64
    public var fractionCompleted: Double {
        guard totalBytesExpected > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytesExpected)
    }
    public var percentage: Int {
        Int(fractionCompleted * 100)
    }

    public init(itemId: UUID, bytesWritten: Int64, totalBytesExpected: Int64) {
        self.itemId = itemId
        self.bytesWritten = bytesWritten
        self.totalBytesExpected = totalBytesExpected
    }
}
