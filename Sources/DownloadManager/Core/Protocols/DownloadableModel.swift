// MARK: - Downloadable Model Protocol
import Foundation

/// Represents a container model (e.g., Course) that contains downloadable items
public protocol DownloadableModel: AnyObject, Identifiable, Codable {
    associatedtype ItemType: DownloadableItem
    
    var id: UUID { get }
    var items: [ItemType] { get set }
    var title: String { get }
    var metadata: [String: String]? { get } // Changed to [String: String] for Codable conformance ease
}