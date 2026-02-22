import Foundation
import AVFoundation
import os

/// Exports audio to MP3 or M4A format
/// Handles conversion from WAV to compressed formats
class AudioExporter {
    enum ExportFormat {
        case mp3
        case m4a
        
        var fileExtension: String {
            switch self {
            case .mp3: return "mp3"
            case .m4a: return "m4a"
            }
        }
    }
    
    enum ExportError: LocalizedError {
        case inputFileNotFound
        case conversionFailed(String)
        case writeError(String)
        
        var errorDescription: String? {
            switch self {
            case .inputFileNotFound:
                return "Input audio file not found"
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .writeError(let reason):
                return "Failed to write output file: \(reason)"
            }
        }
    }
    
    private let logger = Logger(subsystem: "com.speaknow.local", category: "AudioExporter")
    
    /// Export audio file to MP3 or M4A
    func export(inputURL: URL, to format: ExportFormat) throws -> URL {
        // Verify input exists
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ExportError.inputFileNotFound
        }
        
        // Create output URL
        let outputFileName = "\(inputURL.deletingPathExtension().lastPathComponent).\(format.fileExtension)"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: outputURL)
        
        // Get audio asset
        let asset = AVAsset(url: inputURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: Self.exportPresetName(for: format)) else {
            throw ExportError.conversionFailed("Could not create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = Self.avFileType(for: format)
        
        // Export synchronously (block until done)
        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?
        
        exportSession.exportAsynchronously {
            defer { semaphore.signal() }
            
            switch exportSession.status {
            case .completed:
                self.logger.info("Exported to \(format.fileExtension): \(outputURL.path)")
                
            case .failed:
                if let error = exportSession.error {
                    exportError = ExportError.conversionFailed(error.localizedDescription)
                } else {
                    exportError = ExportError.conversionFailed("Unknown error")
                }
                
            case .cancelled:
                exportError = ExportError.conversionFailed("Export cancelled")
                
            default:
                exportError = ExportError.conversionFailed("Unexpected export status: \(exportSession.status)")
            }
        }
        
        // Wait for export to complete
        let waitResult = semaphore.wait(timeout: .now() + 300) // 5 minute timeout
        
        if waitResult == .timedOut {
            exportSession.cancelExport()
            throw ExportError.conversionFailed("Export timed out")
        }
        
        if let error = exportError {
            throw error
        }
        
        // Verify output was created
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.writeError("Output file was not created")
        }
        
        return outputURL
    }
    
    /// Get preset name for AVAssetExportSession
    private static func exportPresetName(for format: ExportFormat) -> String {
        switch format {
        case .mp3:
            // MP3 preset (available on macOS 10.13+)
            if #available(macOS 10.13, *) {
                return AVAssetExportPresetMediumQuality
            }
            return AVAssetExportPresetMediumQuality
            
        case .m4a:
            // M4A/AAC preset
            return AVAssetExportPresetMediumQuality
        }
    }
    
    /// Get AVFileType for output format
    private static func avFileType(for format: ExportFormat) -> AVFileType {
        switch format {
        case .mp3:
            // MP3 file type (available on macOS 10.13+)
            if #available(macOS 10.13, *) {
                return AVFileType(rawValue: "com.mpeg.mp3")
            }
            return AVFileType(rawValue: "com.mpeg.mp3")
            
        case .m4a:
            return .m4a
        }
    }
    
    /// Get file size in MB
    static func fileSize(at url: URL) -> Double? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber {
                return Double(fileSize.int64Value) / (1024 * 1024) // Convert to MB
            }
        } catch {
            return nil
        }
        return nil
    }
}
