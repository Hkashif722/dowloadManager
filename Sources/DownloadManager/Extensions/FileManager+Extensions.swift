// MARK: - FileManager Extensions
import Foundation

public extension FileManager {
    func secureMoveItem(at srcURL: URL, to dstURL: URL, createIntermediateDirectories: Bool = true) throws {
        if createIntermediateDirectories {
            let dstDirectoryURL = dstURL.deletingLastPathComponent()
            if !fileExists(atPath: dstDirectoryURL.path) {
                try createDirectory(at: dstDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        // If a file already exists at the destination, remove it first.
        if fileExists(atPath: dstURL.path) {
            try removeItem(at: dstURL)
        }
        
        try moveItem(at: srcURL, to: dstURL)
    }

    func safeCreateDirectory(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}