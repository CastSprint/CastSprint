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
    static let maximumRestartDelay: TimeInterval = 8.0
    static let maximumPendingStreamChunks = 4
    public weak var delegate: AndroidScreenrecordSessionDelegate?

    private let serial: String
    private let adbPath: String
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stderrBuffer = Data()
    private let decoder = VideoToolboxDecoder()

    private let streamQueue = DispatchQueue(label: "com.castsprint.mac.adb.screenrecord", qos: .userInteractive)
    private let streamChunkAdmission = DispatchSemaphore(value: maximumPendingStreamChunks)
    private var streamBuffer = Data()
    private var isRunning = false
    private var shouldAutoRestart = true
    private var spsData: Data?
    private var ppsData: Data?
    private var hasConfiguredDecoder = false
    private var framePTS: UInt64 = 0
    private var restartWorkItem: DispatchWorkItem?
    private var consecutiveRestarts = 0

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

        try launchScreenrecordProcess(bitrate: bitrate, maxResolution: maxResolution)
    }

    public func stop() {
        self.shouldAutoRestart = false
        self.isRunning = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        consecutiveRestarts = 0
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
        if let pipe = stderrPipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe = nil
        }
    }

    private func launchScreenrecordProcess(bitrate: Int, maxResolution: Int) throws {
        stopProcessInternal()
        stderrBuffer.removeAll(keepingCapacity: true)

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
        let errorPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errorPipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            guard self.streamChunkAdmission.wait(timeout: .now()) == .success else {
                return // Prefer a recoverable video drop to an unbounded memory queue.
            }
            self.streamQueue.async {
                defer { self.streamChunkAdmission.signal() }
                self.consecutiveRestarts = 0
                self.processStreamChunk(chunk)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.streamQueue.async {
                guard let self else { return }
                self.stderrBuffer.append(chunk)
                if self.stderrBuffer.count > 16_384 {
                    self.stderrBuffer.removeFirst(self.stderrBuffer.count - 16_384)
                }
            }
        }

        proc.terminationHandler = { [weak self] process in
            self?.streamQueue.async {
                guard let self = self, self.isRunning else { return }
                if process.terminationStatus != 0 {
                    let detail = String(data: self.stderrBuffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = detail?.isEmpty == false ? detail! : "adb screenrecord exited with status \(process.terminationStatus)"
                    self.delegate?.androidSessionDidEncounterError(
                        self,
                        error: NSError(domain: "CastSprint.AndroidScreenrecord", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
                    )
                }
                if self.shouldAutoRestart {
                    self.scheduleRestart(bitrate: bitrate, maxResolution: maxResolution)
                } else {
                    self.delegate?.androidSessionDidTerminate(self)
                }
            }
        }

        self.process = proc
        self.stdoutPipe = pipe
        self.stderrPipe = errorPipe

        do { try proc.run() } catch {
            self.isRunning = false
            stopProcessInternal()
            throw error
        }
        NSLog("CastSprint: App-less Android USB screenrecord started for serial: %@", serial)
    }

    private func scheduleRestart(bitrate: Int, maxResolution: Int) {
        restartWorkItem?.cancel()
        consecutiveRestarts += 1
        let delay = min(pow(2.0, Double(max(0, consecutiveRestarts - 1))), Self.maximumRestartDelay)
        NSLog("CastSprint: Android screenrecord stopped; retrying in %.1f seconds", delay)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.shouldAutoRestart else { return }
            do {
                try self.launchScreenrecordProcess(bitrate: bitrate, maxResolution: maxResolution)
            } catch {
                self.delegate?.androidSessionDidEncounterError(self, error: error)
                self.scheduleRestart(bitrate: bitrate, maxResolution: maxResolution)
            }
        }
        restartWorkItem = work
        streamQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func processStreamChunk(_ chunk: Data) {
        streamBuffer.append(chunk)

        // Parse a whole batch before removing the consumed prefix. Removing for
        // every NAL repeatedly shifted the buffer and caused avoidable CPU copies.
        var consumedBytes = 0
        var searchOffset = 0
        while let firstStart = findStartCode(in: streamBuffer, startingAt: searchOffset) {
            let payloadStart = firstStart.index + firstStart.length
            guard let nextStart = findStartCode(in: streamBuffer, startingAt: payloadStart) else { break }
            let nalData = streamBuffer.subdata(in: payloadStart..<nextStart.index)
            handleNALUnit(nalData)
            consumedBytes = nextStart.index
            searchOffset = nextStart.index
        }
        if consumedBytes > 0 {
            streamBuffer.removeSubrange(0..<consumedBytes)
        }

        // Prevent memory overflow if parsing lags
        if streamBuffer.count > 4 * 1024 * 1024 {
            streamBuffer.removeAll(keepingCapacity: true)
        }
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

        let ok = decoder.configureH264(configId: 1, csdAnnexB: csd, width: 0, height: 0)
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
