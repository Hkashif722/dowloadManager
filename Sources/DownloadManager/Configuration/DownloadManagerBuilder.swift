// MARK: - Fixed DownloadManagerBuilder
import Foundation

/// Builder for creating configured download manager instances
public class DownloadManagerBuilder<Model: DownloadableModel, Storage: DownloadStorageProtocol>
    where Storage.Model == Model, Storage.Item == Model.ItemType {
    
    private var configuration: DownloadConfiguration?
    private var storage: Storage?
    private var strategyRegistrations: [(Model.ItemType.DownloadType, (DownloadManager<Model, Storage>) -> Void)] = []
    
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
        
        // Store a closure that captures both the strategy and type with their correct types
        let registration: (DownloadManager<Model, Storage>) -> Void = { manager in
            manager.registerStrategy(strategy, for: type)
        }
        
        strategyRegistrations.append((type, registration))
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
        
        // Register strategies using the stored closures that preserve type information
        for (_, registration) in strategyRegistrations {
            registration(manager)
        }
        
        return manager
    }
}
