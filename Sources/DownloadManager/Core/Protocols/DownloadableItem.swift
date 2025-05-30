//
//  DownloadableItem.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//


// MARK: - Downloadable Item Protocol
import Foundation

/// Represents an individual downloadable item (e.g., Module)
public protocol DownloadableItem: AnyObject, Identifiable, Sendable {
    associatedtype DownloadType: DownloadTypeProtocol
    
    var id: UUID { get }
    var title: String { get }
    var downloadURL: URL { get }
    var downloadType: DownloadType { get }
    var localFileURL: URL? { get set }
    var downloadState: DownloadState { get set }
    var downloadProgress: Double { get set } // Represents fraction (0.0 to 1.0)
    var fileSize: Int64? { get set } // Can be updated after download or from headers
    var parentModelId: UUID? { get set }
}
