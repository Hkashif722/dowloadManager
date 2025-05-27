//
//  NetworkClient.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//

//
//  NetworkClient.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//

//
//  NetworkClient.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//

// MARK: - Network Client
import Foundation

// Internal actor to manage URLSession and its delegates with proper concurrency
actor SessionDelegateHandler: NSObject, URLSessionDownloadDelegate {
    private var progressHandlers: [URLSessionTask: @Sendable (Double) -> Void] = [:]
    private var completionHandlers: [URLSessionTask: @Sendable (URL?, Error?) -> Void] = [:]
    
    func setProgressHandler(_ handler: @escaping @Sendable (Double) -> Void, for task: URLSessionTask) {
        progressHandlers[task] = handler
    }
    
    func setCompletionHandler(_ handler: @escaping @Sendable (URL?, Error?) -> Void, for task: URLSessionTask) {
        completionHandlers[task] = handler
    }
    
    private func cleanupHandlers(for task: URLSessionTask) {
        progressHandlers.removeValue(forKey: task)
        completionHandlers.removeValue(forKey: task)
    }

    // MARK: - URLSessionDownloadDelegate
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // CRITICAL: Move file immediately to prevent URLSession from deleting it
        let fileManager = FileManager.default
        
        // Create temp directory path inline to avoid actor isolation issues
        let tempFilesDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("DownloadManager_SafeTemp", isDirectory: true)
        
        // Create a unique filename for our safe temp location
        let safeFileName = "\(UUID().uuidString)_\(downloadTask.taskIdentifier).tmp"
        let safeTempURL = tempFilesDirectory.appendingPathComponent(safeFileName)
        
        var finalLocation: URL?
        var moveError: Error?
        
        do {
            // Ensure our temp directory exists
            try fileManager.createDirectory(at: tempFilesDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Move the file immediately to our safe location
            if fileManager.fileExists(atPath: location.path) {
                // If file already exists at destination, remove it first
                if fileManager.fileExists(atPath: safeTempURL.path) {
                    try fileManager.removeItem(at: safeTempURL)
                }
                try fileManager.moveItem(at: location, to: safeTempURL)
                finalLocation = safeTempURL
                print("NetworkClient: Moved download to safe temp location: \(safeTempURL.path)")
            } else {
                moveError = NSError(domain: "DownloadManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Downloaded file does not exist at expected location: \(location.path)"
                ])
            }
        } catch {
            moveError = error
            print("NetworkClient: Failed to move downloaded file to safe location: \(error.localizedDescription)")
        }
        
        // Now call our completion handler asynchronously with the safe location
        Task {
            await handleDownloadCompletion(task: downloadTask, location: finalLocation, error: moveError)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            await handleTaskCompletion(task: task, error: error)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            await handleProgress(task: downloadTask, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
    
    // Actor-isolated methods to handle delegate callbacks
    private func handleDownloadCompletion(task: URLSessionDownloadTask, location: URL?, error: Error?) {
        completionHandlers[task]?(location, error)
        cleanupHandlers(for: task)
    }
    
    private func handleTaskCompletion(task: URLSessionTask, error: Error?) {
        if let error = error {
            // Check if the error is due to cancellation for resume data
            let nsError = error as NSError
            if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                completionHandlers[task]?(nil, error)
            } else if task.state == .canceling && completionHandlers[task] != nil {
                // If it was cancelled for resume, the pause logic via DownloadTaskCoordinator already handled it.
                // This completion might be called after resume data is obtained.
            }
        }
        // If error is nil and didFinishDownloadingTo was called, completion is already handled.
        if error != nil {
            completionHandlers[task]?(nil, error)
        }
        cleanupHandlers(for: task)
    }
    
    private func handleProgress(task: URLSessionDownloadTask, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandlers[task]?(progress)
        }
    }
    
    // Cleanup method to remove temporary files
    func cleanupTempFiles() {
        let fileManager = FileManager.default
        let tempFilesDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("DownloadManager_SafeTemp", isDirectory: true)
        
        do {
            if fileManager.fileExists(atPath: tempFilesDirectory.path) {
                let tempFiles = try fileManager.contentsOfDirectory(at: tempFilesDirectory, includingPropertiesForKeys: nil)
                for file in tempFiles {
                    try? fileManager.removeItem(at: file)
                }
                print("NetworkClient: Cleaned up \(tempFiles.count) temporary files")
            }
        } catch {
            print("NetworkClient: Error cleaning up temp files: \(error.localizedDescription)")
        }
    }
}

public actor NetworkClient {
    private let urlSession: URLSession
    private let delegateHandler: SessionDelegateHandler
    private let configuration: NetworkConfiguration

    public init(configuration: NetworkConfiguration) {
        self.configuration = configuration
        self.delegateHandler = SessionDelegateHandler()
        let sessionConfig = URLSessionConfiguration.background(withIdentifier: configuration.sessionIdentifier ?? "com.app.downloadmanager.background")
        sessionConfig.allowsCellularAccess = configuration.allowsCellularAccess
        sessionConfig.isDiscretionary = configuration.isDiscretionary
        sessionConfig.sessionSendsLaunchEvents = true
        self.urlSession = URLSession(configuration: sessionConfig, delegate: delegateHandler, delegateQueue: nil)
    }

    public func downloadTask(
        itemId: UUID,
        url: URL,
        headers: [String: String]? = nil,
        resumeData: Data? = nil,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Task<URL, Error> {
        
        var request = URLRequest(url: url)
        headers?.forEach { request.addValue($1, forHTTPHeaderField: $0) }

        let downloadSessionTask: URLSessionDownloadTask
        if let resumeData = resumeData {
            downloadSessionTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadSessionTask = urlSession.downloadTask(with: request)
        }

        return Task {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await delegateHandler.setProgressHandler(progressHandler, for: downloadSessionTask)
                    await delegateHandler.setCompletionHandler({ tempURL, error in
                        if let error = error {
                            continuation.resume(throwing: DownloadError.networkError(error))
                        } else if let tempURL = tempURL {
                            continuation.resume(returning: tempURL)
                        } else {
                            continuation.resume(throwing: DownloadError.unknownNetworkError)
                        }
                    }, for: downloadSessionTask)
                }
            }
        }
    }
    
    /// Creates a URLSessionDownloadTask with handlers properly isolated
    public func createSessionDownloadTask(
        url: URL,
        headers: [String: String]? = nil,
        resumeData: Data? = nil,
        itemId: UUID,
        progressHandler: @Sendable @escaping (Double) -> Void,
        completionHandler: @Sendable @escaping (URL?, Error?) -> Void
    ) async -> URLSessionDownloadTask {
        
        var request = URLRequest(url: url)
        headers?.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        
        let sessionTask: URLSessionDownloadTask
        if let resumeData = resumeData {
            sessionTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            sessionTask = urlSession.downloadTask(with: request)
        }
        
        // Set handlers in a concurrency-safe actor or isolate
        await delegateHandler.setProgressHandler(progressHandler, for: sessionTask)
        await delegateHandler.setCompletionHandler(completionHandler, for: sessionTask)
        
        return sessionTask
    }

    public func invalidateAndCancel() {
        Task {
            await delegateHandler.cleanupTempFiles()
        }
        urlSession.invalidateAndCancel()
    }
}
