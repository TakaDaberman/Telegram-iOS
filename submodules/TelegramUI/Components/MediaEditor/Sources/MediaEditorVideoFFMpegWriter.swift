import Foundation
import UIKit
import CoreMedia
import FFMpegBinding
import ImageDCT

final class MediaEditorVideoFFMpegWriter: MediaEditorVideoExportWriter {
    public static let registerFFMpegGlobals: Void = {
        FFMpegGlobals.initializeGlobals()
        return
    }()
    
    let ffmpegWriter = FFMpegVideoWriter()
    var pool: CVPixelBufferPool?
        
    func setup(configuration: MediaEditorVideoExport.Configuration, outputPath: String) {
        let _ = MediaEditorVideoFFMpegWriter.registerFFMpegGlobals
        
        let width = Int32(configuration.dimensions.width)
        let height = Int32(configuration.dimensions.height)
        
        let bufferOptions: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3 as NSNumber
        ]
        let pixelBufferOptions: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as NSNumber,
            kCVPixelBufferWidthKey as String: UInt32(width),
            kCVPixelBufferHeightKey as String: UInt32(height)
        ]
        
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, bufferOptions as CFDictionary, pixelBufferOptions as CFDictionary, &pool)
        guard let pool else {
            self.status = .failed
            return
        }
        self.pool = pool
        
        if !self.ffmpegWriter.setup(withOutputPath: outputPath, width: width, height: height, bitrate: 200 * 1000, framerate: 30) {
            self.status = .failed
        }
    }
    
    func setupVideoInput(configuration: MediaEditorVideoExport.Configuration, preferredTransform: CGAffineTransform?, sourceFrameRate: Float) {
        
    }
    
    func setupAudioInput(configuration: MediaEditorVideoExport.Configuration) {
        
    }
    
    func startWriting() -> Bool {
        if self.status != .failed {
            self.status = .writing
            return true
        } else {
            return false
        }
    }
    
    func startSession(atSourceTime time: CMTime) {
        
    }
    
    func finishWriting(completion: @escaping () -> Void) {
        self.ffmpegWriter.finalizeVideo()
        self.status = .completed
        completion()
    }
    
    func cancelWriting() {
        
    }
    
    func requestVideoDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        queue.async {
            block()
        }
    }
    
    func requestAudioDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        
    }
    
    var isReadyForMoreVideoData: Bool {
        return true
    }
    
    func appendVideoBuffer(_ buffer: CMSampleBuffer) -> Bool {
        return false
    }
    
    func appendPixelBuffer(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        let width = Int32(CVPixelBufferGetWidth(buffer))
        let height = Int32(CVPixelBufferGetHeight(buffer))
        let bytesPerRow = Int32(CVPixelBufferGetBytesPerRow(buffer))
        
        let frame = FFMpegAVFrame(pixelFormat: .YUVA, width: width, height: height)
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
        let src = CVPixelBufferGetBaseAddress(buffer)
        
        splitRGBAIntoYUVAPlanes(
            src,
            frame.data[0],
            frame.data[1],
            frame.data[2],
            frame.data[3],
            width,
            height,
            bytesPerRow,
            true,
            true
        )

        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
        
        return self.ffmpegWriter.encode(frame)
    }
    
    func markVideoAsFinished() {
        
    }
    
    var pixelBufferPool: CVPixelBufferPool? {
        return self.pool
    }
    
    var isReadyForMoreAudioData: Bool {
        return false
    }
    
    func appendAudioBuffer(_ buffer: CMSampleBuffer) -> Bool {
        return false
    }
    
    func markAudioAsFinished() {
        
    }
    
    var status: ExportWriterStatus = .unknown
    
    var error: Error?
}
