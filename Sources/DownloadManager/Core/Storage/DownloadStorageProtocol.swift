//
//  DownloadStorageProtocol.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//


// MARK: - Download Storage Protocol
import Foundation

public protocol DownloadStorageProtocol: Sendable {
    associatedtype Model: DownloadableModel
    associatedtype Item: DownloadableItem where Item.DownloadType == Model.ItemType.DownloadType // Ensure consistency
    
    // Model operations
    func saveModel(_ model: Model) async throws
    func fetchModel(by id: UUID) async throws -> Model?
    func fetchAllModels() async throws -> [Model]
    func deleteModel(_ model: Model) async throws // Also handles deletion of its items' records and files
    
    // Item operations (within a model context or standalone)
    func saveItem(_ item: Item) async throws // Removed 'to model' as item should have parentModelId
    func fetchItem(by id: UUID) async throws -> Item?
    func fetchItems(for modelId: UUID) async throws -> [Item]
    
    /// Updates the state and progress of an item.
    /// If localURL is nil, it implies the file is not yet downloaded or has been deleted.
    func updateItem(_ item: Item) async throws // Consolidates state, progress, localURL updates

    // Direct Download Record Management (more granular control if needed, supplements updateItem)
    func saveDownloadRecord(itemId: UUID, state: DownloadState, progress: Double, localURL: URL?, fileSize: Int64?) async throws
    func fetchDownloadRecord(itemId: UUID) async throws -> (state: DownloadState, progress: Double, localURL: URL?, fileSize: Int64?)?
    func deleteDownloadRecord(itemId: UUID) async throws // Only deletes the record, not necessarily the file
    
    func clearAllData() async throws // For complete cleanup
}
