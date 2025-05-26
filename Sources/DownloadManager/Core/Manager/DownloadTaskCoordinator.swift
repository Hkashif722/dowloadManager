// MARK: - Download Task Coordinator
import Foundation

actor DownloadTaskCoordinator {
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var resumeDataStore: [UUID: Data] = [:]

    var activeTaskCount: Int {
        activeTasks.count
    }

    func addTask(_ task: URLSessionDownloadTask, for itemId: UUID) {
        activeTasks[itemId] = task
        task.resume() // Start the task immediately upon adding
    }

    func task(for itemId: UUID) -> URLSessionDownloadTask? {
        activeTasks[itemId]
    }

    func removeTask(for itemId: UUID) {
        activeTasks.removeValue(forKey: itemId)
        resumeDataStore.removeValue(forKey: itemId) // Clear resume data once task is fully removed
    }

    func pauseTask(_ itemId: UUID) async throws {
        guard let task = activeTasks[itemId] else {
            // Task might have already completed or been removed
            print("DownloadTaskCoordinator: No active task found to pause for item \(itemId)")
            return
        }
        
        // For URLSessionDownloadTask, calling cancel(byProducingResumeData:) is the way to "pause"
        // The completion handler of this cancel will provide the resumeData.
        let data = await task.cancelForResumeData()
        self.resumeDataStore[itemId] = data
        // Task is removed from activeTasks upon cancellation in the session delegate or completion handler
        // So, we might not need to explicitly remove it here if DownloadManager handles it.
        // However, to be safe and ensure it's not considered "active" if pause is called directly:
        activeTasks.removeValue(forKey: itemId)
         print("DownloadTaskCoordinator: Task for item \(itemId) paused, resume data stored: \(data != nil)")
    }

    // Resume will involve creating a new task with resumeData, handled by DownloadManager/NetworkClient
    func getResumeData(for itemId: UUID) -> Data? {
        return resumeDataStore.removeValue(forKey: itemId) // Consume resume data
    }

    func cancelTask(_ itemId: UUID) async throws {
        activeTasks[itemId]?.cancel()
        activeTasks.removeValue(forKey: itemId)
        resumeDataStore.removeValue(forKey: itemId) // Also clear any stored resume data
        print("DownloadTaskCoordinator: Task for item \(itemId) cancelled.")
    }

    func isDownloading(_ itemId: UUID) -> Bool {
        return activeTasks[itemId] != nil && activeTasks[itemId]?.state == .running
    }

    func allTaskIdentifiers() -> [UUID] {
        return Array(activeTasks.keys)
    }

    func cleanup() async {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        resumeDataStore.removeAll()
        print("DownloadTaskCoordinator: All tasks cleaned up.")
    }
}

extension URLSessionDownloadTask {
    func cancelForResumeData() async -> Data? {
        await withCheckedContinuation { continuation in
            self.cancel { resumeData in
                continuation.resume(returning: resumeData)
            }
        }
    }
}