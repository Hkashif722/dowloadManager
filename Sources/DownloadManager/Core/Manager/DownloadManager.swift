// MARK: - Download Manager
import Foundation
import Combine // For @Published

@MainActor
public final class DownloadManager<Model: DownloadableModel, Storage: DownloadStorageProtocol>
    where Storage.Model == Model, Storage.Item == Model.ItemType {
    
    public typealias Item = Model.ItemType
    public typealias DownloadType = Item.DownloadType
    
    // MARK: - Properties
    private let configuration: DownloadConfiguration
    private let storage: Storage
    private let networkClient: NetworkClient
    private let taskCoordinator: DownloadTaskCoordinator
    private var downloadStrategies: [String: any DownloadStrategy] = [:] // Keyed by DownloadType.rawValue

    private var itemQueue: [Item] = [] // Queue for items waiting for download slot
    private let queueAccess = DispatchQueue(label: "com.downloadManager.itemQueueAccess")


    // MARK: - Publishers
    @Published public private(set) var downloadStates: [UUID: DownloadState] = [:]
    @Published public private(set) var downloadProgress: [UUID: Double] = [:]
    @Published public private(set) var activeDownloadsCount: Int = 0

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    public init(configuration: DownloadConfiguration, storage: Storage) {
        self.configuration = configuration
        self.storage = storage
        self.networkClient = NetworkClient(configuration: configuration.networkConfiguration)
        self.taskCoordinator = DownloadTaskCoordinator()

        // Initialize states and progress from storage
        
        self.loadInitialStatesAndProgress()

    }
    
    deinit {
        // Capture taskCoordinator to avoid capturing self
        let coordinator = taskCoordinator
        let networkClient = networkClient
        Task.detached {
            await coordinator.cleanup()
            await networkClient.invalidateAndCancel()
        }
    }

    /// Loads initial states and progress from storage. Should be called during init.
        internal func loadInitialStatesAndProgress()  {
            Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    let items = try await storage.fetchAllModels().flatMap { $0.items }
                    var initialStates: [UUID: DownloadState] = [:]
                    var initialProgress: [UUID: Double] = [:]
                    for item in items {
                        initialStates[item.id] = item.downloadState
                        initialProgress[item.id] = item.downloadProgress
                    }
                    self.downloadStates = initialStates
                    self.downloadProgress = initialProgress
                } catch {
                    print("DownloadManager: Failed to load initial states from storage: \(error)")
                }
            }
        }
    
    /// Resumes any downloads that were in 'downloading' or 'queued' state.
    public func initializePendingTasksFromStorage() async {
        do {
            let allItems = try await storage.fetchAllModels().flatMap { $0.items }
            let pendingItems = allItems.filter { $0.downloadState == .downloading || $0.downloadState == .queued || $0.downloadState == .paused }

            for item in pendingItems {
                print("DownloadManager: Found pending item from previous session: \(item.title) (\(item.id)) with state \(item.downloadState)")
                // If paused, user needs to manually resume.
                // If was downloading or queued, attempt to re-queue.
                if item.downloadState == .downloading || item.downloadState == .queued {
                    do {
                        // Reset state to queued to ensure it goes through the process logic.
                        try await updateItemStateAndStorage(item.id, state: .queued, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)
                        try await downloadItemInternal(item, isResumingPending: true)
                    } catch {
                        print("DownloadManager: Failed to re-queue pending item \(item.id): \(error)")
                        try? await updateItemStateAndStorage(item.id, state: .failed, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)
                    }
                }
            }
        } catch {
            print("DownloadManager: Error initializing pending tasks from storage: \(error)")
        }
    }


    // MARK: - Public API
    
    public func fileExists(at path: String, modelId: UUID? = nil, itemId: UUID? = nil) async -> (exists: Bool, url: URL?) {
        let fileManager = FileManager.default
        
        // 1. Direct lookup by itemId (most efficient)
        if let itemId = itemId {
            do {
                if let item = try await storage.fetchItem(by: itemId),
                   let localURL = item.localFileURL,
                   fileManager.fileExists(atPath: localURL.path) {
                    if path.isEmpty || localURL.path.contains(path) || localURL.lastPathComponent == path {
                        return (true, localURL)
                    }
                }
            } catch {
                print("DownloadManager fileExists (itemId: \(itemId)): Storage fetch error: \(error.localizedDescription)")
            }
        }
        
        // 2. Check relative to standard downloads directory (if path is relative)
        // This assumes 'path' could be like "DownloadTypeRawValue/ParentModelID/ItemID.extension" or part of it
        let components = path.split(separator: "/").map(String.init)
        if components.count > 1 { // Potentially a structured path
            // Attempt to construct full path based on configuration
            // This part requires knowing the structure or iterating.
            // For a more robust search, iterating through stored items is better.
        }

        // 3. Search in model's items or all items
        do {
            let itemsToSearch: [Item]
            if let modelId = modelId, let model = try await storage.fetchModel(by: modelId) {
                itemsToSearch = model.items
            } else if itemId == nil { // Avoid re-fetching all if itemId was already tried
                itemsToSearch = try await storage.fetchAllModels().flatMap { $0.items }
            } else {
                itemsToSearch = []
            }

            for item in itemsToSearch {
                if let localURL = item.localFileURL {
                    let fmPath = localURL.path // Use .path for file system operations
                    if fileManager.fileExists(atPath: fmPath) && (fmPath.contains(path) || localURL.lastPathComponent == path) {
                        return (true, localURL)
                    }
                }
            }
        } catch {
            print("DownloadManager fileExists (path: \(path)): Storage search error: \(error.localizedDescription)")
        }

        // 4. Fallback: Try constructing path with downloadsDirectory if path is a full name like "itemID.ext"
        // This is less reliable without knowing the exact structure.
        // Consider a more exhaustive search if necessary or rely on itemId.
        let searchFullPath = configuration.downloadsDirectory.appendingPathComponent(path)
        if fileManager.fileExists(atPath: searchFullPath.path) {
            return (true, searchFullPath)
        }

        return (false, nil)
    }
    
    public func registerStrategy<S: DownloadStrategy>(_ strategy: S, for type: DownloadType) where S.Item == Item {
        downloadStrategies[type.rawValue] = strategy
    }
    
    /// Download an item. It will be added to a queue and processed.
    public func downloadItem(_ item: Item, createModelIfNeeded: @escaping () async throws -> Model) async throws {
        // Ensure item has an ID if it's new
        if item.id == UUID() { // Assuming default UUID() means it's not set, adjust if necessary
            fatalError("Item must have a valid ID to be downloaded.") // Or assign one
        }
        
        // 0. Check if already downloading or queued via taskCoordinator or our internal queue
        if await taskCoordinator.task(for: item.id) != nil || queueAccess.sync(execute: { itemQueue.contains(where: { $0.id == item.id }) }) {
            print("DownloadManager: Item \(item.id) is already downloading or queued.")
            // Optionally, update its state to queued if it was, for example, failed and retried.
            if downloadStates[item.id] == .failed {
                 try await updateItemStateAndStorage(item.id, state: .queued, progress: 0, localURL: nil, fileSize: nil)
            }
            // return // Do not throw, just acknowledge it's known. Or throw specific error.
            // For now, let it proceed to internal logic which handles existing tasks.
        }

        // 1. Validate download type (early exit)
        guard DownloadType.allCases.contains(where: { $0.rawValue == item.downloadType.rawValue }) else {
            throw DownloadError.unsupportedType(item.downloadType.rawValue)
        }

        // 2. Handle Model Association
        var mutableItem = item // Make a mutable copy to update parentModelId if needed
        var parentModel: Model?
        if let parentId = mutableItem.parentModelId {
            parentModel = try await storage.fetchModel(by: parentId)
        }

        if parentModel == nil {
            parentModel = try await createModelIfNeeded()
            try await storage.saveModel(parentModel!) // Save new model
            mutableItem.parentModelId = parentModel!.id // Assign parent ID to the item copy
        }
        
        // Ensure item is part of the model's list in storage
        if !(parentModel!.items.contains(where: { $0.id == mutableItem.id })) {
            parentModel!.items.append(mutableItem) // Add mutableItem to ensure parentModelId is correct
            try await storage.saveModel(parentModel!)
        }
        
        // 3. Save/Update item in storage BEFORE queuing, setting state to queued.
        // This ensures the item exists in storage for subsequent operations.
        mutableItem.downloadState = .queued
        mutableItem.downloadProgress = 0.0
        try await storage.saveItem(mutableItem) // Save the potentially modified item (with parentModelId)
        
        // Update local state publishers
        updateLocalState(itemId: mutableItem.id, state: .queued, progress: 0.0)

        // 4. Add to internal queue and process
        try await downloadItemInternal(mutableItem)
    }

    private func downloadItemInternal(_ item: Item, isResumingPending: Bool = false) async throws {
        queueAccess.sync(flags: .barrier) {
            if !itemQueue.contains(where: { $0.id == item.id }) {
                itemQueue.append(item)
            }
        }
        if !isResumingPending { // Only log if it's a new request, not a startup resume
            print("DownloadManager: Item \(item.id) added to queue. Queue size: \(itemQueue.count)")
        }
        await processQueue()
    }
    
    private func processQueue() async {
        guard await taskCoordinator.activeTaskCount < configuration.maxConcurrentDownloads else {
            activeDownloadsCount = await taskCoordinator.activeTaskCount // Update count
            return // Wait for a slot to open
        }

        let itemToDownload = queueAccess.sync {
            itemQueue.isEmpty ? nil : itemQueue.removeFirst()
        }

        guard let item = itemToDownload else {
            activeDownloadsCount = await taskCoordinator.activeTaskCount // Update count
            return // Queue is empty
        }
        
        // Double check if task already exists for this item (e.g., if processQueue is called multiple times rapidly)
        if await taskCoordinator.task(for: item.id) != nil {
            print("DownloadManager: Task for item \(item.id) already started. Skipping in processQueue.")
            await processQueue() // Try next item
            return
        }

        activeDownloadsCount = await taskCoordinator.activeTaskCount + 1 // Tentatively increment

        print("DownloadManager: Starting download for item \(item.id) - \(item.title)")
        
        // Fetch the latest item state from storage, as it might have changed (e.g. paused)
        guard var currentItem = try? await storage.fetchItem(by: item.id) else {
            print("DownloadManager: Item \(item.id) not found in storage before starting download. Aborting this item.")
            await MainActor.run { self.downloadStates[item.id] = .failed } // Update UI state
            activeDownloadsCount = await taskCoordinator.activeTaskCount // Recalculate true count
            await processQueue() // process next
            return
        }

        // If item was paused and is now being processed, it means it was resumed.
        // If it's still paused in storage, it shouldn't be processed.
        if currentItem.downloadState == .paused {
            print("DownloadManager: Item \(item.id) is paused. Re-queuing if necessary or ignoring. Current design implies resumeDownload should handle this.")
            // If it's paused, it shouldn't be in the active processing queue unless explicitly resumed.
            // For safety, put it back if it was in itemQueue and shouldn't be processed.
            // However, resumeDownload calls downloadItemInternal, so this path might be hit.
            // The key is that startDownload will fetch resumeData if item.state is paused.
        }
        
        // Update state to downloading right before the task
        try? await updateItemStateAndStorage(currentItem.id, state: .downloading, progress: currentItem.downloadProgress, localURL: currentItem.localFileURL, fileSize: currentItem.fileSize)

        // Start the actual download
        Task { // Detached task to not block processQueue
            do {
                try await startDownload(item: currentItem)
            } catch {
                print("DownloadManager: Failed to start download for item \(item.id): \(error.localizedDescription)")
                try? await handleDownloadError(for: item.id, error: error)
            }
            activeDownloadsCount = await taskCoordinator.activeTaskCount
            await processQueue() // Process next item
        }
    }


    public func downloadModel(_ model: Model) async throws {
        try await storage.saveModel(model) // Ensure model is saved first
        for item in model.items {
            // Check current state from storage or cache to avoid re-downloading completed items
            let currentItemState = await MainActor.run { self.downloadStates[item.id] } ?? .notDownloaded
            if currentItemState != .downloaded && currentItemState != .downloading && currentItemState != .queued {
                do {
                    // Pass a closure that just returns the known model
                    try await downloadItem(item) {
                        return model // This closure is only called if model needs creation, which it shouldn't here.
                    }
                } catch DownloadError.taskAlreadyExists {
                    print("DownloadManager: Task for item \(item.id) in model \(model.id) already exists or is queued.")
                } catch {
                    print("DownloadManager: Failed to queue download for item \(item.id) in model \(model.id): \(error)")
                    // Optionally collect errors and report them
                }
            }
        }
    }
    
    public func pauseDownload(itemId: UUID) async throws {
        guard let item = try await storage.fetchItem(by: itemId) else {
            throw DownloadError.itemNotFound
        }
        guard item.downloadState == .downloading || item.downloadState == .queued else {
            print("DownloadManager: Item \(itemId) is not in a pausable state (\(item.downloadState)).")
            return // Not an error, just nothing to pause
        }

        // If it's in the processing queue but not yet an active task, remove from queue.
        let removedFromQueue = queueAccess.sync(flags: .barrier) {
            if let index = itemQueue.firstIndex(where: { $0.id == itemId }) {
                itemQueue.remove(at: index)
                return true
            }
            return false
        }

        if removedFromQueue {
            print("DownloadManager: Item \(itemId) removed from pending queue for pausing.")
            try await updateItemStateAndStorage(itemId, state: .paused, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)
        } else if await taskCoordinator.task(for: itemId) != nil {
            // If it's an active task, tell coordinator to pause (which means cancel and get resume data)
            try await taskCoordinator.pauseTask(itemId) // This will trigger cancel(byProducingResumeData:)
            // The resume data will be caught by the task's completion handler in startDownload or NetworkClient
            // State update to .paused should happen once resumeData is confirmed or task is truly stopped.
            // For now, optimistically update. If pause fails, state might need revert or be error.
            // The `taskCoordinator.pauseTask` should ideally handle storing resume data.
            // The `startDownload` completion/error handling should use this resume data if the error is a cancellation.
             print("DownloadManager: Pause requested for active task \(itemId).")
             // State update will be handled by the download completion/error path for cancellations.
             // Here, we ensure storage and UI reflect the intent to pause.
             try await updateItemStateAndStorage(itemId, state: .paused, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)
        } else {
            print("DownloadManager: No active task or queued item found to pause for \(itemId). State: \(item.downloadState).")
            // If state is downloading but no task, it's an inconsistent state. Mark as paused.
            if item.downloadState == .downloading {
                 try await updateItemStateAndStorage(itemId, state: .paused, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)
            }
        }
        activeDownloadsCount = await taskCoordinator.activeTaskCount
        await processQueue() // Check if new tasks can start
    }
    
    public func resumeDownload(itemId: UUID) async throws {
        guard var item = try await storage.fetchItem(by: itemId) else {
            throw DownloadError.itemNotFound
        }
        
        guard item.downloadState == .paused || item.downloadState == .failed else {
            print("DownloadManager: Item \(itemId) is not in a resumable state (\(item.downloadState)).")
            // If already downloading or queued, this is a no-op.
            if item.downloadState == .downloading || item.downloadState == .queued { return }
            throw DownloadError.downloadFailed("Item is not paused or failed.") // Or a more specific error
        }

        // Update state to queued and re-add to download queue
        item.downloadState = .queued // Progress remains from where it paused or 0 if failed
        if item.downloadState == .failed { // If resuming a failed download, reset progress
            item.downloadProgress = 0.0
            item.localFileURL = nil // Clear previous partial file if any
        }
        try await storage.updateItem(item)
        updateLocalState(itemId: item.id, state: .queued, progress: item.downloadProgress)
        
        // Re-trigger downloadItemInternal which will add to queue and process
        try await downloadItemInternal(item)
    }
    
    public func cancelDownload(itemId: UUID) async throws {
        guard let item = try await storage.fetchItem(by: itemId) else {
            // If item not found, nothing to cancel from storage perspective
            // Still, try to cancel any active network task
            try await taskCoordinator.cancelTask(itemId) // Fire and forget if item is not in DB
            print("DownloadManager: Item \(itemId) not found in storage, but attempted to cancel any orphaned network task.")
            await MainActor.run { // Ensure UI reflects cancellation even if item was gone
                self.downloadStates[itemId] = .notDownloaded
                self.downloadProgress[itemId] = 0.0
            }
            return
        }

        let previousState = item.downloadState
        try await updateItemStateAndStorage(itemId, state: .cancelling, progress: item.downloadProgress, localURL: item.localFileURL, fileSize: item.fileSize)


        // If it's in the processing queue but not yet an active task, remove from queue.
        let removedFromQueue = queueAccess.sync(flags: .barrier) {
            if let index = itemQueue.firstIndex(where: { $0.id == itemId }) {
                itemQueue.remove(at: index)
                return true
            }
            return false
        }

        if removedFromQueue {
            print("DownloadManager: Item \(itemId) removed from pending queue for cancellation.")
        } else if await taskCoordinator.task(for: itemId) != nil {
             // If it's an active task, tell coordinator to cancel
            try await taskCoordinator.cancelTask(itemId)
             print("DownloadManager: Cancel requested for active task \(itemId).")
        } else {
            print("DownloadManager: No active task or queued item found to cancel for \(itemId). State: \(previousState).")
        }
        
        // Delete partial file if exists
        if let tempLocalURL = item.localFileURL, item.downloadState != .downloaded { // only delete if not fully downloaded.
            do {
                if FileManager.default.fileExists(atPath: tempLocalURL.path) {
                    try FileManager.default.removeItem(at: tempLocalURL)
                    print("DownloadManager: Deleted partial file at \(tempLocalURL.path) for cancelled item \(itemId).")
                }
            } catch {
                print("DownloadManager: Could not delete partial file for item \(itemId) at \(tempLocalURL.path): \(error)")
                // Don't throw; cancellation should still proceed.
            }
        }

        try await updateItemStateAndStorage(itemId, state: .notDownloaded, progress: 0.0, localURL: nil, fileSize: nil)
        await taskCoordinator.removeTask(for: itemId) // Ensure coordinator is clean
        activeDownloadsCount = await taskCoordinator.activeTaskCount
        await processQueue() // Check if new tasks can start
    }
    
    public func deleteDownload(itemId: UUID, modelId: UUID? = nil) async throws {
        // 1. Attempt to cancel if it's downloading or queued
        let itemState = await MainActor.run { self.downloadStates[itemId] }
        if itemState == .downloading || itemState == .queued || itemState == .paused || itemState == .cancelling {
            try? await cancelDownload(itemId: itemId) // cancel first, ignore error if already cancelled or not found
        }
        
        // 2. Fetch item from storage
        guard var item = try await storage.fetchItem(by: itemId) else {
            // If not in storage, maybe it's an orphaned file? Or just nothing to do.
            print("DownloadManager: Item \(itemId) not found in storage for deletion.")
            // Clean up UI state just in case
            await MainActor.run {
                self.downloadStates.removeValue(forKey: itemId)
                self.downloadProgress.removeValue(forKey: itemId)
            }
            return
        }
        
        // 3. Delete the physical file
        if let localURL = item.localFileURL {
            do {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                    print("DownloadManager: Deleted file for item \(itemId) at \(localURL.path)")
                }
                item.localFileURL = nil // Clear the local URL
            } catch {
                // Log error, but proceed to update state in DB.
                print("DownloadManager: Failed to delete file \(localURL.path) for item \(itemId): \(error.localizedDescription)")
                throw DownloadError.fileOperationFailed("Failed to delete file at \(localURL.path)", error)
            }
        }
        
        // 4. Update item state in storage and local cache/publishers
        item.downloadState = .notDownloaded
        item.downloadProgress = 0.0
        item.fileSize = nil
        try await storage.updateItem(item) // This saves the item with cleared localFileURL and state.
        try await storage.deleteDownloadRecord(itemId: itemId) // Also ensure download record is cleared if it's separate

        updateLocalState(itemId: itemId, state: .notDownloaded, progress: 0.0)
        
        // 5. Optionally remove item from its parent model if it's no longer relevant
        if let parentId = item.parentModelId, var parentModel = try? await storage.fetchModel(by: parentId) {
            parentModel.items.removeAll(where: { $0.id == itemId })
            try? await storage.saveModel(parentModel)
             print("DownloadManager: Item \(itemId) removed from parent model \(parentId).")
        }
        activeDownloadsCount = await taskCoordinator.activeTaskCount // Recalculate just in case
    }

    public func getLocalURL(for itemId: UUID) async -> URL? {
        if let item = try? await storage.fetchItem(by: itemId) {
            return item.localFileURL
        }
        return nil
    }
    
    public func clearAllDownloadsAndData() async throws {
        // 1. Cancel all ongoing and queued downloads
        let allItemIds = await taskCoordinator.allTaskIdentifiers() + queueAccess.sync { itemQueue.map { $0.id } }
        for itemId in Set(allItemIds) { // Use Set to avoid duplicates
            try? await cancelDownload(itemId: itemId)
        }
        itemQueue.removeAll()

        // 2. Delete all downloaded files by iterating through storage
        let allModels = try await storage.fetchAllModels()
        for model in allModels {
            for item in model.items {
                if let localURL = item.localFileURL, FileManager.default.fileExists(atPath: localURL.path) {
                    try? FileManager.default.removeItem(at: localURL)
                }
            }
        }
        // Or, more drastically, wipe the entire configured downloads directory
        // try? FileManager.default.removeItem(at: configuration.downloadsDirectory)
        // try? FileManager.default.createDirectory(at: configuration.downloadsDirectory, withIntermediateDirectories: true, attributes: nil)


        // 3. Clear all data from storage
        try await storage.clearAllData()

        // 4. Reset local state
        await MainActor.run {
            self.downloadStates.removeAll()
            self.downloadProgress.removeAll()
            self.activeDownloadsCount = 0
        }
        print("DownloadManager: All downloads and associated data have been cleared.")
    }


    // MARK: - Private Methods
    
    private func startDownload(item: Item) async throws {
            var currentItem = item // Make mutable copy to update progress/state during download

            // 1. Prepare download (strategy or default)
            let preparation: DownloadPreparation
            let strategy = downloadStrategies[currentItem.downloadType.rawValue] // Cast to concrete type with Item assoc.
            
            // Check for resume data if item was paused
            var resumeData: Data? = nil
            if currentItem.downloadState == .paused || currentItem.downloadProgress > 0 && currentItem.downloadProgress < 1.0 { // Also consider resuming if partially downloaded
                resumeData = await taskCoordinator.getResumeData(for: currentItem.id)
                if resumeData != nil {
                    print("DownloadManager: Found resume data for item \(currentItem.id). Attempting to resume.")
                }
            }

            if let concreteStrategy = strategy as? DownloadStrategyHelper<Item>, concreteStrategy.itemTypeMatches(currentItem) {
                 preparation = try await concreteStrategy.prepareDownload(for: currentItem, resumeData: resumeData)
            } else {
                preparation = DownloadPreparation(url: currentItem.downloadURL, resumeData: resumeData)
            }

            // Capture only the necessary values that are Sendable
            let item = currentItem
            let itemProgress = currentItem.downloadProgress
            let taskCoordinator = self.taskCoordinator
            let storage = self.storage
            let downloadType = currentItem.downloadType
            let configuration = self.configuration
            

            // 2. Create URLSessionDownloadTask via NetworkClient
            let sessionTask = await networkClient.createSessionDownloadTask(
                url: preparation.url,
                headers: preparation.headers,
                resumeData: preparation.resumeData, // Use resumeData from preparation
                itemId: currentItem.id,
                progressHandler: { progressValue in
                    Task { @MainActor in
                        // Update progress on main actor without capturing self
                        await MainActor.run {
                            self.downloadProgress[item.id] = progressValue
                        }
                        
                        // Update storage in a separate task
                        if var storedItem = try? await storage.fetchItem(by: item.id) {
                            storedItem.downloadProgress = progressValue
                            storedItem.downloadState = .downloading
                            try? await storage.updateItem(storedItem)
                        }
                    }
                },
                completionHandler: { tempLocalURL, error in
                    Task {
                        await taskCoordinator.removeTask(for: item.id)
                        let activeCount = await taskCoordinator.activeTaskCount
                        
                        await MainActor.run {
                            self.activeDownloadsCount = activeCount
                        }
                        
                        defer {
                            Task { await self.processQueue() }
                        }
                        
                        if let error = error {
                            // Clean up any temp file if it exists
                            if let tempURL = tempLocalURL, FileManager.default.fileExists(atPath: tempURL.path) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            
                            // Check if error is NSURLErrorCancelled and resume data might be available (for pause)
                            let nsError = error as NSError
                            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                                if let resumeDataFromCoordinator = await taskCoordinator.getResumeData(for: item.id) {
                                    print("DownloadManager: Task for \(item.id) was cancelled for pause, resumeData obtained (\(resumeDataFromCoordinator.count) bytes). State set to Paused.")
                                    let currentProgress = await MainActor.run { self.downloadProgress[item.id] } ?? itemProgress
                                    try? await self.updateItemStateAndStorage(item.id, state: .paused, progress: currentProgress)
                                    return
                                } else {
                                    let currentState = await MainActor.run { self.downloadStates[item.id] }
                                    if currentState == .cancelling {
                                        print("DownloadManager: Task for \(item.id) was cancelled by user. State set to NotDownloaded.")
                                        try? await self.updateItemStateAndStorage(item.id, state: .notDownloaded, progress: 0, localURL: nil, fileSize: nil)
                                        return
                                    }
                                }
                            }
                            // Genuine error
                            print("DownloadManager: Download failed for item \(item.id) with error: \(error.localizedDescription)")
                            try? await self.handleDownloadError(for: item.id, error: error)
                            return
                        }
                        
                        guard let tempURL = tempLocalURL else {
                            print("DownloadManager: Download completed for item \(item.id) but temporary URL is missing.")
                            try? await self.handleDownloadError(for: item.id, error: DownloadError.downloadFailed("Temporary file URL missing after download."))
                            return
                        }
                        
                        // Verify the temp file actually exists before processing
                        guard FileManager.default.fileExists(atPath: tempURL.path) else {
                            print("DownloadManager: Downloaded file does not exist at temporary location: \(tempURL.path)")
                            try? await self.handleDownloadError(for: item.id, error: DownloadError.fileOperationFailed("Downloaded file missing at temporary location", nil))
                            return
                        }
                        
                        // 3. Process and move file (strategy or default)
                        do {
                            let finalURL: URL
                            var processedURL = tempURL
                            
                            // Fetch file size from tempURL attributes before any processing
                            let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
                            let fileSize = attributes?[.size] as? Int64
                            
                            // Re-fetch strategy from self to ensure we have the latest
                            let currentStrategy = await self.downloadStrategies[downloadType.rawValue]
                            
                            if let concreteStrategy = currentStrategy as? DownloadStrategyHelper<Item>, concreteStrategy.itemTypeMatches(item) {
                                processedURL = try await concreteStrategy.processDownloadedFile(at: tempURL, for: item)
                                // Validate after processing if strategy requires it
                                let isValid = try await concreteStrategy.validateDownload(at: processedURL, for: item)
                                if !isValid {
                                    throw DownloadError.strategyError("Download validation failed by custom strategy.")
                                }
                            }
                            
                            finalURL = try await self.moveFileToPermanentLocation(processedURL, for: item)
                            print("DownloadManager: File for item \(item.id) moved to \(finalURL.path)")
                            
                            // Clean up temp file after successful move (only if it's different from final location)
                            if processedURL != finalURL && FileManager.default.fileExists(atPath: processedURL.path) {
                                try? FileManager.default.removeItem(at: processedURL)
                                print("DownloadManager: Cleaned up temporary file at \(processedURL.path)")
                            }
                            
                            // 4. Update item state to .downloaded and save final state
                            try await self.updateItemStateAndStorage(item.id, state: .downloaded, progress: 1.0, localURL: finalURL, fileSize: fileSize)
                            print("DownloadManager: Item \(item.id) successfully downloaded and processed.")
                            
                        } catch {
                            print("DownloadManager: Error processing or moving file for item \(item.id): \(error.localizedDescription)")
                            try? await self.handleDownloadError(for: item.id, error: error)
                            
                            // Cleanup temporary file
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try? FileManager.default.removeItem(at: tempURL)
                                print("DownloadManager: Cleaned up temporary file after error: \(tempURL.path)")
                            }
                        }
                    }
                }
            )
        
        // 3. Add to TaskCoordinator
        await taskCoordinator.addTask(sessionTask, for: currentItem.id)
        // taskCoordinator starts the task upon adding.
    }
    
    private func moveFileToPermanentLocation(_ sourceURL: URL, for item: Item) async throws -> URL {
        let fileManager = FileManager.default
        
        // Verify source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw DownloadError.fileOperationFailed("Source file does not exist at path: \(sourceURL.path)", nil)
        }
        
        let destinationDir = configuration.downloadsDirectory
            .appendingPathComponent(item.downloadType.rawValue, isDirectory: true)
            .appendingPathComponent(item.parentModelId?.uuidString ?? "orphaned_items", isDirectory: true)
        
        do {
            try fileManager.safeCreateDirectory(at: destinationDir)
        } catch {
            throw DownloadError.fileOperationFailed("Failed to create destination directory: \(destinationDir.path)", error)
        }
        
        // Determine file extension more robustly
        var fileExtension = ""
        if !item.downloadType.fileExtension.isEmpty {
            fileExtension = item.downloadType.fileExtension
        } else if !sourceURL.pathExtension.isEmpty {
            fileExtension = sourceURL.pathExtension
        } else {
            // Fallback: try to detect from downloaded file
            if let detectedExtension = detectFileExtension(at: sourceURL) {
                fileExtension = detectedExtension
            } else {
                fileExtension = "bin" // Generic binary extension as last resort
            }
        }
        
        // Remove leading dot if present
        if fileExtension.hasPrefix(".") {
            fileExtension = String(fileExtension.dropFirst())
        }
        
        let fileName = "\(item.id.uuidString).\(fileExtension)"
        let finalURL = destinationDir.appendingPathComponent(fileName)
        
        do {
            try fileManager.secureMoveItem(at: sourceURL, to: finalURL)
            print("DownloadManager: Successfully moved file from \(sourceURL.path) to \(finalURL.path)")
            return finalURL
        } catch {
            throw DownloadError.fileOperationFailed("Failed to move file from \(sourceURL.path) to \(finalURL.path)", error)
        }
    }


    private func handleDownloadError(for itemId: UUID, error: Error) async throws {
        let currentProgress = await MainActor.run { self.downloadProgress[itemId] } ?? 0.0
        // Preserve localFileURL if error is recoverable or for resume, otherwise clear it.
        // For a generic failure, we assume it's not easily resumable from the same partial file unless network layer says so.
        try await updateItemStateAndStorage(itemId, state: .failed, progress: currentProgress, localURL: nil, fileSize: nil) // Clear local URL on failure
        print("DownloadManager: Item \(itemId) marked as failed. Error: \(error.localizedDescription)")
    }

    // Helper to update both local publishers and persistent storage for an item's state.
    private func updateItemStateAndStorage(_ itemId: UUID, state: DownloadState, progress: Double? = nil, localURL: URL? = nil, fileSize: Int64? = nil) async throws {
        // Fetch the most recent version of the item from storage
        guard var itemToUpdate = try await storage.fetchItem(by: itemId) else {
            print("DownloadManager: updateItemStateAndStorage - Item \(itemId) not found in storage. Cannot update.")
            // Update local state anyway so UI can reflect change attempt
            await MainActor.run {
                self.downloadStates[itemId] = state
                if let progress = progress { self.downloadProgress[itemId] = progress }
            }
            throw DownloadError.itemNotFound
        }

        // Update fields
        itemToUpdate.downloadState = state
        if let progress = progress {
            itemToUpdate.downloadProgress = max(0.0, min(1.0, progress)) // Clamp progress
        }
        if localURL != itemToUpdate.localFileURL { // Only update if changed
             itemToUpdate.localFileURL = localURL
        }
        if fileSize != itemToUpdate.fileSize {
            itemToUpdate.fileSize = fileSize
        }


        // Persist to storage
        try await storage.updateItem(itemToUpdate)
        
        // Update local @Published properties on the main actor
        updateLocalState(itemId: itemId, state: state, progress: itemToUpdate.downloadProgress)
    }
    
    // Helper to update @Published properties on the main actor
    @MainActor
    private func updateLocalState(itemId: UUID, state: DownloadState, progress: Double) {
        downloadStates[itemId] = state
        downloadProgress[itemId] = progress
    }

    // Helper to deal with type erasure of DownloadStrategy's associated type `Item`
     private struct DownloadStrategyHelper<SpecificItem: DownloadableItem>: DownloadStrategy {
        typealias Item = SpecificItem
        
        private let _prepareDownload: @Sendable  (Item, Data?) async throws -> DownloadPreparation
        private let _processDownloadedFile: @Sendable (URL, Item) async throws -> URL
        private let _validateDownload: @Sendable  (URL, Item) async throws -> Bool
        private let _itemTypeMatches: @Sendable (any DownloadableItem) -> Bool

        init<S: DownloadStrategy>(_ strategy: S) where S.Item == Item {
            _prepareDownload = strategy.prepareDownload
            _processDownloadedFile = strategy.processDownloadedFile
            _validateDownload = strategy.validateDownload
            _itemTypeMatches = { item in item is Item }
        }

        func prepareDownload(for item: Item, resumeData: Data?) async throws -> DownloadPreparation {
            try await _prepareDownload(item, resumeData)
        }

        func processDownloadedFile(at temporaryURL: URL, for item: Item) async throws -> URL {
            try await _processDownloadedFile(temporaryURL, item)
        }

        func validateDownload(at fileURL: URL, for item: Item) async throws -> Bool {
            try await _validateDownload(fileURL, item)
        }
        
        func itemTypeMatches(_ item: any DownloadableItem) -> Bool {
            _itemTypeMatches(item)
        }
    }
}

extension DownloadManager {
    
    // Add this helper method to detect file extension from file content
    private func detectFileExtension(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count >= 4 else {
            return nil
        }
        
        let bytes = data.prefix(4)
        
        // Check for common file signatures
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { // PNG
            return "png"
        } else if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { // JPEG
            return "jpg"
        } else if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4B, 0x05, 0x06]) { // ZIP
            return "zip"
        } else if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { // PDF
            return "pdf"
        } else if String(data: data.prefix(100), encoding: .utf8) != nil { // Text-based content
            return "txt"
        }
        
        return nil
    }

}
