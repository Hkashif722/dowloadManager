// MARK: - Sources/DownloadManager/Configuration/DownloadManagerBuilder.swift

import Foundation

/// Builder for creating configured download manager instances
public class DownloadManagerBuilder<Model: DownloadableModel, Storage: DownloadStorageProtocol>
    where Storage.Model == Model, Storage.Item == Model.ItemType {
    
    private var configuration: DownloadConfiguration?
    private var storage: Storage?
    private var strategies: [(Model.ItemType.DownloadType, any DownloadStrategy)] = []
    
    public init() {}
    
    public func with(configuration: DownloadConfiguration) -> Self {
        self.configuration = configuration
        return self
    }
    
    public func with(storage: Storage) -> Self {
        self.storage = storage
        return self
    }
    
    public func withStrategy<S: DownloadStrategy>(_ strategy: S, for type: Model.ItemType.DownloadType) -> Self
        where S.Item == Model.ItemType {
        strategies.append((type, strategy))
        return self
    }
    
    @MainActor
    public func build() throws -> DownloadManager<Model, Storage> {
        guard let configuration = configuration else {
            throw DownloadError.missingConfiguration
        }
        
        guard let storage = storage else {
            throw DownloadError.missingStorage
        }
        
        let manager = DownloadManager(configuration: configuration, storage: storage)
        
        for (type, strategy) in strategies {
            manager.registerStrategy(strategy, for: type)
        }
        
        return manager
    }
}
