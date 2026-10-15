// AndroidScreenrecordSession.swift — Native App-Less Android USB Screen Mirroring via ADB
// CastSprint Multimedia Engineering
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

public protocol AndroidScreenrecordSessionDelegate: AnyObject {
    func androidSession(_ session: AndroidScreenrecordSession, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, pts: UInt64)
    func androidSessionDidEncounterError(_ session: AndroidScreenrecordSession, error: Error)
    func androidSessionDidTerminate(_ session: AndroidScreenrecordSession)
}

public final class AndroidScreenrecordSession: NSObject, VideoDecoderDelegate {
    public weak var delegate: AndroidScreenrecordSessionDelegate?

    private let serial: String
    private let adbPath: String
    private var process: Process?
    private var stdoutPipe: Pipe?
    private let decoder = VideoToolboxDecoder()

    private let streamQueue = DispatchQueue(label: "com.castsprint.mac.adb.screenrecord", qos: .userInteractive)
    private var streamBuffer = Data()
    private var isRunning = false
    private var shouldAutoRestart = true
    private var spsData: Data?
    private var ppsData: Data?
    private var hasConfiguredDecoder = false
    private var framePTS: UInt64 = 0

    public init(serial: String, adbPath: String) {
        self.serial = serial
        self.adbPath = adbPath
        super.init()
        self.decoder.delegate = self
    }

    deinit {
        stop()
    }

    public func start(bitrate: Int = 12_000_000, maxResolution: Int = 1920) throws {
        guard !isRunning else { return }
        self.isRunning = true
        self.shouldAutoRestart = true
        self.streamBuffer.removeAll()
        self.hasConfiguredDecoder = false
        self.spsData = nil
        self.ppsData = nil

        launchScreenrecordProcess(bitrate: bitrate, maxResolution: maxResolution)
    }

    public func stop() {
        self.shouldAutoRestart = false
        self.isRunning = false
        stopProcessInternal()
        decoder.teardown()
    }

    private func stopProcessInternal() {
        if let proc = process {
            proc.terminationHandler = nil
            if proc.isRunning {
                proc.terminate()
            }
            process = nil
        }
        if let pipe = stdoutPipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe = nil
        }
    }

    private func launchScreenrecordProcess(bitrate: Int, maxResolution: Int) {
        stopProcessInternal()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments = [
            "-s", serial,
            "exec-out",
            "screenrecord",
            "--output-format=h264",
            "--bit-rate=\(bitrate)",
            "-"
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.streamQueue.async {
                self?.processStreamChunk(chunk)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            self?.streamQueue.async {
                guard let self = self, self.isRunning else { return }
                if self.shouldAutoRestart {
                    NSLog("CastSprint: Android screenrecord boundary reached. Seamlessly restarting stream...")
                    self.launchScreenrecordProcess(bitrate: bitrate, maxResolution: maxResolution)
                } else {
                    self.delegate?.androidSessionDidTerminate(self)
                }
            }
        }

        self.process = proc
        self.stdoutPipe = pipe

        do {
            try proc.run()
            NSLog("CastSprint: App-less Android USB screenrecord started for serial: %@", serial)
        } catch {
            NSLog("CastSprint: Failed to launch screenrecord: %@", error.localizedDescription)
            delegate?.androidSessionDidEncounterError(self, error: error)
        }
    }

    private func processStreamChunk(_ chunk: Data) {
        streamBuffer.append(chunk)

        // Parse Annex-B NAL units delimited by 0x00000001 or 0x000001
        while let nalRange = findNextNALUnitRange(in: streamBuffer) {
            let nalData = streamBuffer.subdata(in: nalRange.unitRange)
            streamBuffer.removeSubrange(0..<nalRange.nextStartIndex)
            handleNALUnit(nalData)
        }

        // Prevent memory overflow if parsing lags
        if streamBuffer.count > 4 * 1024 * 1024 {
            streamBuffer.removeAll(keepingCapacity: true)
        }
    }

    private struct NALRange {
        let unitRange: Range<Data.Index>
        let nextStartIndex: Int
    }

    private func findNextNALUnitRange(in data: Data) -> NALRange? {
        guard data.count > 4 else { return nil }

        // Find start code for first NALU
        guard let firstStart = findStartCode(in: data, startingAt: 0) else { return nil }
        let payloadStart = firstStart.index + firstStart.length

        // Find next start code defining the end of this NALU
        guard let nextStart = findStartCode(in: data, startingAt: payloadStart) else {
            return nil // Incomplete NALU, wait for more data
        }

        return NALRange(
            unitRange: payloadStart..<nextStart.index,
            nextStartIndex: nextStart.index
        )
    }

    private func findStartCode(in data: Data, startingAt: Int) -> (index: Int, length: Int)? {
        guard startingAt + 3 < data.count else { return nil }
        let count = data.count
        var i = startingAt

        while i + 3 < count {
            if data[i] == 0 && data[i + 1] == 0 {
                if data[i + 2] == 1 {
                    return (i, 3)
                } else if i + 3 < count && data[i + 2] == 0 && data[i + 3] == 1 {
                    return (i, 4)
                }
            }
            i += 1
        }
        return nil
    }

    private func handleNALUnit(_ nalu: Data) {
        guard !nalu.isEmpty else { return }
        let nalType = nalu[0] & 0x1F

        switch nalType {
        case 7: // SPS
            self.spsData = nalu
            checkAndConfigureDecoder()

        case 8: // PPS
            self.ppsData = nalu
            checkAndConfigureDecoder()

        case 5: // IDR Keyframe
            guard hasConfiguredDecoder else { return }
            framePTS += 16666 // ~60 FPS (16.6ms per frame)
            let annexB = prependStartCode(nalu)
            _ = decoder.decode(configId: 1, isKeyframe: true, ptsMicros: framePTS, annexBData: annexB)

        case 1: // Non-IDR Slice (P-frame)
            guard hasConfiguredDecoder else { return }
            framePTS += 16666
            let annexB = prependStartCode(nalu)
            _ = decoder.decode(configId: 1, isKeyframe: false, ptsMicros: framePTS, annexBData: annexB)

        default:
            break
        }
    }

    private func checkAndConfigureDecoder() {
        guard let sps = spsData, let pps = ppsData, !hasConfiguredDecoder else { return }

        var csd = Data()
        csd.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        csd.append(sps)
        csd.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        csd.append(pps)

        let ok = decoder.configureH264(configId: 1, csdAnnexB: csd, width: 1920, height: 1080)
        if ok {
            self.hasConfiguredDecoder = true
            NSLog("CastSprint: App-less Android VideoToolbox decompressor configured successfully")
        }
    }

    private func prependStartCode(_ data: Data) -> Data {
        var prefixed = Data(capacity: 4 + data.count)
        prefixed.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        prefixed.append(data)
        return prefixed
    }

    // MARK: - VideoDecoderDelegate
    public func didDecompressPixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64) {
        delegate?.androidSession(self, didOutputPixelBuffer: pixelBuffer, pts: ptsMicros)
    }

    public func didEncounterDecoderError(_ error: Error) {
        delegate?.androidSessionDidEncounterError(self, error: error)
    }
}
