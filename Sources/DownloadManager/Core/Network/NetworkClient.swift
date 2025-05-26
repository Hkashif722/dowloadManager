//
//  to.swift
//  DownloadManager
//
//  Created by Kashif Hussain on 26/05/25.
//


// MARK: - Network Client
import Foundation

// Internal class to manage URLSession and its delegates
class SessionDelegateHandler: NSObject, URLSessionDownloadDelegate {
    var progressHandlers: [URLSessionTask: (Double) -> Void] = [:]
    var completionHandlers: [URLSessionTask: (URL?, Error?) -> Void] = [:]

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        completionHandlers[downloadTask]?(location, nil)
        cleanupHandlers(for: downloadTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if the error is due to cancellation for resume data
            let nsError = error as NSError
            if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                 completionHandlers[task]?(nil, error)
            } else if task.state == .canceling && completionHandlers[task] != nil {
                // If it was cancelled for resume, the pause logic via DownloadTaskCoordinator already handled it.
                // This completion might be called after resume data is obtained.
                // Only call completion if it's a "terminal" cancel, not one for pausing.
                // This part is tricky; URLSession calls this even for cancel(byProducingResumeData:).
                // The DownloadManager's pause logic should take precedence.
                // If completionHandlers[task] is still here, it means it wasn't a pause or the pause logic didn't clear it.
                // For now, we assume pause logic clears the handler or the task.
            }
        }
        // If error is nil and didFinishDownloadingTo was called, completion is already handled.
        // If error is nil and didFinishDownloadingTo was NOT called (should not happen for download tasks),
        // it's an unexpected state.
        if error != nil {
            completionHandlers[task]?(nil, error)
        }
        cleanupHandlers(for: task)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandlers[downloadTask]?(progress)
        }
    }
    
    private func cleanupHandlers(for task: URLSessionTask) {
        progressHandlers.removeValue(forKey: task)
        completionHandlers.removeValue(forKey: task)
    }
}


public class NetworkClient {
    private let urlSession: URLSession
    private let delegateHandler: SessionDelegateHandler
    private let configuration: NetworkConfiguration

    public init(configuration: NetworkConfiguration) {
        self.configuration = configuration
        self.delegateHandler = SessionDelegateHandler()
        let sessionConfig = URLSessionConfiguration.background(withIdentifier: configuration.sessionIdentifier ?? "com.app.downloadmanager.background")
        sessionConfig.allowsCellularAccess = configuration.allowsCellularAccess
        sessionConfig.isDiscretionary = configuration.isDiscretionary // iOS can delay tasks for system optimization
        sessionConfig.sessionSendsLaunchEvents = true // Important for background downloads
        self.urlSession = URLSession(configuration: sessionConfig, delegate: delegateHandler, delegateQueue: nil) // nil queue means a serial operation queue
    }

    func downloadTask(
        itemId: UUID, // Added to manage resume data
        url: URL,
        headers: [String: String]? = nil,
        resumeData: Data? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> Task<URL, Error> {
        
        var request = URLRequest(url: url)
        headers?.forEach { request.addValue($1, forHTTPHeaderField: $0) }

        let downloadSessionTask: URLSessionDownloadTask
        if let resumeData = resumeData {
            downloadSessionTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadSessionTask = urlSession.downloadTask(with: request)
        }
        
        // Associate task with its item ID early for delegate logic if needed
        // downloadSessionTask.taskDescription = itemId.uuidString

        return Task {
            try await withCheckedThrowingContinuation { continuation in
                delegateHandler.progressHandlers[downloadSessionTask] = progressHandler
                delegateHandler.completionHandlers[downloadSessionTask] = { tempURL, error in
                    if let error = error {
                        continuation.resume(throwing: DownloadError.networkError(error))
                    } else if let tempURL = tempURL {
                        continuation.resume(returning: tempURL)
                    } else {
                        // Should not happen: no error, no URL
                        continuation.resume(throwing: DownloadError.unknownNetworkError)
                    }
                }
                // Task is resumed by DownloadTaskCoordinator after being added to it
                // downloadSessionTask.resume() // Do not resume here, let coordinator do it.
            }
        }
    }
    
    /// A separate method to directly create the URLSessionDownloadTask, which DownloadManager will pass to DownloadTaskCoordinator
    func createSessionDownloadTask(
        url: URL,
        headers: [String: String]? = nil,
        resumeData: Data? = nil,
        itemId: UUID, // For associating handlers
        progressHandler: @escaping (Double) -> Void,
        completionHandler: @escaping (URL?, Error?) -> Void
    ) -> URLSessionDownloadTask {
        var request = URLRequest(url: url)
        headers?.forEach { request.addValue($1, forHTTPHeaderField: $0) }

        let sessionTask: URLSessionDownloadTask
        if let resumeData = resumeData {
            sessionTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            sessionTask = urlSession.downloadTask(with: request)
        }
        
        delegateHandler.progressHandlers[sessionTask] = progressHandler
        delegateHandler.completionHandlers[sessionTask] = completionHandler
        
        return sessionTask
    }


    func invalidateAndCancel() {
        urlSession.invalidateAndCancel() // For cleanup, e.g., when DownloadManager is deinitialized
    }
}
