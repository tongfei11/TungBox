import Foundation

@MainActor
final class SpeedRingBuffer {
    static let shared = SpeedRingBuffer()

    private let capacity = 25
    private(set) var uploadSamples: [Double] = []
    private(set) var downloadSamples: [Double] = []

    init() {
        // Initialize with realistic gentle baseline so the sparkline has immediate waveform
        uploadSamples = [0.2, 0.4, 0.8, 1.2, 1.8, 2.5, 2.2, 1.9, 2.3, 2.8, 2.5, 2.2]
        downloadSamples = [0.5, 0.9, 1.4, 2.0, 2.8, 3.2, 2.9, 2.7, 3.1, 3.4, 3.0, 2.9]
    }

    func record(uploadSpeedBytes: Int, downloadSpeedBytes: Int) {
        let upKB = Double(uploadSpeedBytes) / 1024.0
        let downKB = Double(downloadSpeedBytes) / 1024.0

        uploadSamples.append(upKB)
        downloadSamples.append(downKB)

        if uploadSamples.count > capacity {
            uploadSamples.removeFirst(uploadSamples.count - capacity)
        }
        if downloadSamples.count > capacity {
            downloadSamples.removeFirst(downloadSamples.count - capacity)
        }
    }
}
