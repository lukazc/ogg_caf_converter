import Flutter
import AVFoundation

public class OggCafConverterPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ogg_caf_converter",
            binaryMessenger: registrar.messenger()
        )
        let instance = OggCafConverterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "repairWalk":
            guard let args = call.arguments as? [String: Any],
                  let audioData = args["audio"] as? FlutterStandardTypedData,
                  let sampleRate = args["sampleRate"] as? Double,
                  let channels = args["channels"] as? Int,
                  let framesPerPacket = args["framesPerPacket"] as? Int
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let walker = RepairWalker(
                data: audioData.data,
                sampleRate: sampleRate,
                channels: channels,
                framesPerPacket: framesPerPacket
            )
            let sizes = walker.walk()
            result(sizes)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

class RepairWalker {
    private let data: Data
    private let sampleRate: Double
    private let channels: Int
    private let framesPerPacket: Int
    private let expectMono: Bool
    private let minPacketSize = 10
    private let maxPacketSize = 2000

    init(data: Data, sampleRate: Double, channels: Int, framesPerPacket: Int) {
        self.data = data
        self.sampleRate = sampleRate
        self.channels = channels
        self.framesPerPacket = framesPerPacket
        self.expectMono = (channels == 1)
    }

    func walk() -> [Int] {
        if data.isEmpty { return [] }
        let dominantToc = findDominantToc()

        guard let mainDecoder = OpusStatefulDecoder(
            sampleRate: sampleRate, channels: channels, framesPerPacket: framesPerPacket
        ) else { return [] }

        var sizes: [Int] = []
        var offset = 0

        while offset < data.count {
            let searchEnd = min(offset + maxPacketSize, data.count)
            var bestPos = -1
            var bestHasDominant = false

            for pos in (offset + minPacketSize)..<searchEnd {
                let toc = data[pos]
                if !isValidOpusToc(toc) { continue }
                let hasDominant = dominantToc.contains(Int(toc))
                let candidatePacket = data.subdata(in: offset..<pos)

                guard let tempDecoder = OpusStatefulDecoder(
                    sampleRate: sampleRate, channels: channels, framesPerPacket: framesPerPacket
                ) else { continue }

                if tempDecoder.tryDecode(packet: candidatePacket) {
                    if bestPos < 0 || (hasDominant && !bestHasDominant) {
                        bestPos = pos
                        bestHasDominant = hasDominant
                    }
                }
            }

            if bestPos > 0 {
                let size = bestPos - offset
                sizes.append(size)
                _ = mainDecoder.tryDecode(packet: data.subdata(in: offset..<bestPos))
                offset = bestPos
            } else {
                let remaining = data.count - offset
                if remaining >= minPacketSize { sizes.append(remaining) }
                break
            }
        }
        return sizes
    }

    private func isValidOpusToc(_ byte: UInt8) -> Bool {
        if (byte & 0x03) == 0x03 { return false }
        if expectMono && ((byte >> 2) & 1) != 0 { return false }
        return true
    }

    private func findDominantToc() -> Set<Int> {
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        for i in 0..<data.count {
            if isValidOpusToc(data[i]) { histogram[Int(data[i])] += 1; total += 1 }
        }
        let noiseFloor = Double(total) / 96.0 * 2.0
        var result = Set<Int>()
        for j in 0..<256 {
            if Double(histogram[j]) > noiseFloor { result.insert(j) }
        }
        return result
    }
}

class OpusStatefulDecoder {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let framesPerPacket: Int

    init?(sampleRate: Double, channels: Int, framesPerPacket: Int) {
        self.framesPerPacket = framesPerPacket
        var inDesc = AudioStreamBasicDescription()
        inDesc.mSampleRate = sampleRate
        inDesc.mFormatID = kAudioFormatOpus
        inDesc.mFormatFlags = 0
        inDesc.mBytesPerPacket = 0
        inDesc.mFramesPerPacket = UInt32(framesPerPacket)
        inDesc.mBytesPerFrame = 0
        inDesc.mChannelsPerFrame = UInt32(channels)
        inDesc.mBitsPerChannel = 0

        var outDesc = AudioStreamBasicDescription()
        outDesc.mSampleRate = sampleRate
        outDesc.mFormatID = kAudioFormatLinearPCM
        outDesc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        outDesc.mBytesPerPacket = UInt32(2 * channels)
        outDesc.mFramesPerPacket = 1
        outDesc.mBytesPerFrame = UInt32(2 * channels)
        outDesc.mChannelsPerFrame = UInt32(channels)
        outDesc.mBitsPerChannel = 16

        guard let inFmt = AVAudioFormat(streamDescription: &inDesc),
              let outFmt = AVAudioFormat(streamDescription: &outDesc),
              let conv = AVAudioConverter(from: inFmt, to: outFmt)
        else { return nil }

        self.converter = conv
        self.outFormat = outFmt
    }

    func tryDecode(packet: Data) -> Bool {
        guard let inBuffer = AVAudioCompressedBuffer(
            format: converter.inputFormat, packetCapacity: 1, maximumPacketSize: packet.count
        ) else { return false }

        inBuffer.packetDescriptions!.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count)
        )
        packet.copyBytes(to: inBuffer.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
        inBuffer.packetCount = 1
        inBuffer.byteLength = UInt32(packet.count)

        let frameCapacity = AVAudioFrameCount(framesPerPacket)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: frameCapacity)
        else { return false }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            inputStatus.pointee = .haveData
            return inBuffer
        }
        return error == nil
    }
}
