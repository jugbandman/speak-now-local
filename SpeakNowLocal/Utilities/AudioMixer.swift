import Foundation
import AVFoundation

class AudioMixer {
    /// Mix two WAV files together by averaging samples, writing to Constants.tempMixedAudioURL.
    /// Falls back gracefully if one URL is nil or the file is empty.
    static func mix(micURL: URL?, systemURL: URL?) throws -> URL {
        let outputURL = Constants.tempMixedAudioURL

        // If only one source is available, return it directly (copy to mixed URL for consistency)
        switch (micURL, systemURL) {
        case (nil, nil):
            throw AudioMixerError.noInputFiles
        case (let url?, nil):
            try FileManager.default.copyOrReplace(from: url, to: outputURL)
            return outputURL
        case (nil, let url?):
            try FileManager.default.copyOrReplace(from: url, to: outputURL)
            return outputURL
        case (let micURL?, let sysURL?):
            return try mixBothFiles(micURL: micURL, systemURL: sysURL, outputURL: outputURL)
        }
    }

    private static func mixBothFiles(micURL: URL, systemURL: URL, outputURL: URL) throws -> URL {
        let micFile = try AVAudioFile(forReading: micURL)
        let sysFile = try AVAudioFile(forReading: systemURL)

        let format = micFile.processingFormat
        let micFrames = AVAudioFrameCount(micFile.length)
        let sysFrames = AVAudioFrameCount(sysFile.length)
        let totalFrames = max(micFrames, sysFrames)

        guard totalFrames > 0 else {
            throw AudioMixerError.emptyFiles
        }

        let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: micFrames)!
        let sysBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sysFrames)!
        let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        outBuffer.frameLength = totalFrames

        try micFile.read(into: micBuffer)
        try sysFile.read(into: sysBuffer)

        let channelCount = Int(format.channelCount)

        for ch in 0..<channelCount {
            guard let outData = outBuffer.floatChannelData?[ch] else { continue }
            let micData = micBuffer.floatChannelData?[ch]
            let sysData = sysBuffer.floatChannelData?[ch]

            for i in 0..<Int(totalFrames) {
                let micSample: Float = (micData != nil && i < Int(micFrames)) ? micData![i] : 0.0
                let sysSample: Float = (sysData != nil && i < Int(sysFrames)) ? sysData![i] : 0.0
                outData[i] = (micSample + sysSample) * 0.5
            }
        }

        // Write mixed output
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: false
        )
        try outputFile.write(from: outBuffer)

        return outputURL
    }
}

enum AudioMixerError: LocalizedError {
    case noInputFiles
    case emptyFiles

    var errorDescription: String? {
        switch self {
        case .noInputFiles:
            return "No audio files provided to mix."
        case .emptyFiles:
            return "Both audio files are empty."
        }
    }
}

private extension FileManager {
    func copyOrReplace(from source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        try copyItem(at: source, to: destination)
    }
}
