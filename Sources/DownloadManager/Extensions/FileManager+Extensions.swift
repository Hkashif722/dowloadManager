// MARK: - FileManager Extensions
import Foundation

public extension FileManager {
    func secureMoveItem(at srcURL: URL, to dstURL: URL, createIntermediateDirectories: Bool = true) throws {
        // Verify source exists
        guard fileExists(atPath: srcURL.path) else {
            throw NSError(domain: "FileManagerError", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Source file does not exist at path: \(srcURL.path)"
            ])
        }
        
        if createIntermediateDirectories {
            let dstDirectoryURL = dstURL.deletingLastPathComponent()
            if !fileExists(atPath: dstDirectoryURL.path) {
                do {
                    try createDirectory(at: dstDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                    print("FileManager: Created directory: \(dstDirectoryURL.path)")
                } catch {
                    throw NSError(domain: "FileManagerError", code: 1002, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to create destination directory: \(dstDirectoryURL.path)",
                        NSUnderlyingErrorKey: error
                    ])
                }
            }
        }
        
        // If a file already exists at the destination, remove it first.
        if fileExists(atPath: dstURL.path) {
            do {
                try removeItem(at: dstURL)
                print("FileManager: Removed existing file at destination: \(dstURL.path)")
            } catch {
                throw NSError(domain: "FileManagerError", code: 1003, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to remove existing file at destination: \(dstURL.path)",
                    NSUnderlyingErrorKey: error
                ])
            }
        }
        
        do {
            try moveItem(at: srcURL, to: dstURL)
            print("FileManager: Successfully moved file from \(srcURL.path) to \(dstURL.path)")
        } catch {
            // Provide more detailed error information
            let sourceExists = fileExists(atPath: srcURL.path)
            let destDirExists = fileExists(atPath: dstURL.deletingLastPathComponent().path)
            
            let errorMessage = """
            Failed to move file:
            - Source: \(srcURL.path) (exists: \(sourceExists))
            - Destination: \(dstURL.path)
            - Destination directory: \(dstURL.deletingLastPathComponent().path) (exists: \(destDirExists))
            - Original error: \(error.localizedDescription)
            """
            
            throw NSError(domain: "FileManagerError", code: 1004, userInfo: [
                NSLocalizedDescriptionKey: errorMessage,
                NSUnderlyingErrorKey: error
            ])
        }
    }

    func safeCreateDirectory(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            do {
                try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                print("FileManager: Created directory: \(url.path)")
            } catch {
                throw NSError(domain: "FileManagerError", code: 1005, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create directory: \(url.path)",
                    NSUnderlyingErrorKey: error
                ])
            }
        }
    }
    
    func safeCopyItem(at srcURL: URL, to dstURL: URL, createIntermediateDirectories: Bool = true) throws {
        // Verify source exists
        guard fileExists(atPath: srcURL.path) else {
            throw NSError(domain: "FileManagerError", code: 1006, userInfo: [
                NSLocalizedDescriptionKey: "Source file does not exist at path: \(srcURL.path)"
            ])
        }
        
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
        
        try copyItem(at: srcURL, to: dstURL)
        print("FileManager: Successfully copied file from \(srcURL.path) to \(dstURL.path)")
    }
}
