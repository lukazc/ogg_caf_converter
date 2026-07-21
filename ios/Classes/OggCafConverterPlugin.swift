import Flutter
import AVFoundation

/// The Flutter plugin class for ogg_caf_converter.
///
/// Registers a method channel that the Dart side uses to invoke
/// AVAudioConverter-based Opus decode verification during CAF repair.
public class OggCafConverterPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ogg_caf_converter/opus_decode",
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
        case "decodePackets":
            guard let args = call.arguments as? [String: Any],
                  let packetList = args["packets"] as? [FlutterStandardTypedData],
                  let sampleRate = args["sampleRate"] as? Double,
                  let channels = args["channels"] as? Int,
                  let framesPerPacket = args["framesPerPacket"] as? Int
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Expected packets list, sampleRate, channels, framesPerPacket",
                    details: nil
                ))
                return
            }

            let rawPackets = packetList.map { $0.data }
            let decoder = OpusDecoder(
                sampleRate: sampleRate,
                channels: channels,
                framesPerPacket: framesPerPacket
            )

            let results = decoder.decodeBatch(packets: rawPackets)
            result(results)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Decodes a batch of raw Opus packets using AVAudioConverter.
///
/// Maintains converter state across the batch so that consecutive
/// packets are decoded in context (needed for correct Opus PLC and
/// overlap-add continuity).
class OpusDecoder {
    private let sampleRate: Double
    private let channels: Int
    private let framesPerPacket: Int

    init(sampleRate: Double, channels: Int, framesPerPacket: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.framesPerPacket = framesPerPacket
    }

    /// Decodes each packet in `packets` sequentially using AVAudioConverter.
    ///
    /// Decoder state is maintained across packets.  A decode failure at
    /// packet N means subsequent packets may also fail (broken state).
    ///
    /// Returns a list of booleans (as NSNumber) — `true` for each
    /// packet that decoded successfully.
    func decodeBatch(packets: [Data]) -> [NSNumber] {
        guard let converter = makeConverter() else {
            return Array(repeating: false, count: packets.count)
        }
        let outFormat = converter.outputFormat

        var results = [NSNumber]()
        for packet in packets {
            let success = decodeOne(
                converter: converter,
                outFormat: outFormat,
                packet: packet
            )
            results.append(success as NSNumber)
        }
        return results
    }

    // MARK: - Private

    private func decodeOne(
        converter: AVAudioConverter,
        outFormat: AVAudioFormat,
        packet: Data
    ) -> Bool {
        let inBuffer = AVAudioCompressedBuffer(
            format: converter.inputFormat,
            packetCapacity: 1,
            maximumPacketSize: packet.count
        )
        packet.copyBytes(
            to: inBuffer.data.assumingMemoryBound(to: UInt8.self),
            count: packet.count
        )
        inBuffer.packetCount = 1
        inBuffer.byteLength = UInt32(packet.count)

        guard let outBuffer = makePCMBuffer(format: outFormat) else {
            return false
        }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            inputStatus.pointee = .haveData
            return inBuffer
        }

        // convert() returns Bool in newer AVFAudio (false on error).
        // Check error pointer as a fallback for older API surfaces.
        return error == nil
    }

    // MARK: - Private

    private func makeConverter() -> AVAudioConverter? {
        guard let inDesc = opusStreamDescription() else { return nil }
        guard let outDesc = pcmStreamDescription() else { return nil }
        let inFormat = AVAudioFormat(streamDescription: inDesc)
        let outFormat = AVAudioFormat(streamDescription: outDesc)
        guard let inFmt = inFormat, let outFmt = outFormat else { return nil }
        return AVAudioConverter(from: inFmt, to: outFmt)
    }

    private func opusStreamDescription() -> UnsafePointer<AudioStreamBasicDescription>? {
        let descPtr = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
        descPtr.pointee.mSampleRate = sampleRate
        descPtr.pointee.mFormatID = kAudioFormatOpus
        descPtr.pointee.mFormatFlags = 0
        descPtr.pointee.mBytesPerPacket = 0
        descPtr.pointee.mFramesPerPacket = UInt32(framesPerPacket)
        descPtr.pointee.mBytesPerFrame = 0
        descPtr.pointee.mChannelsPerFrame = UInt32(channels)
        descPtr.pointee.mBitsPerChannel = 0
        return UnsafePointer(descPtr)
    }

    private func pcmStreamDescription() -> UnsafePointer<AudioStreamBasicDescription>? {
        let descPtr = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
        descPtr.pointee.mSampleRate = sampleRate
        descPtr.pointee.mFormatID = kAudioFormatLinearPCM
        descPtr.pointee.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        descPtr.pointee.mBytesPerPacket = UInt32(2 * channels)
        descPtr.pointee.mFramesPerPacket = 1
        descPtr.pointee.mBytesPerFrame = UInt32(2 * channels)
        descPtr.pointee.mChannelsPerFrame = UInt32(channels)
        descPtr.pointee.mBitsPerChannel = 16
        return UnsafePointer(descPtr)
    }

    private func makePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(framesPerPacket)
        return AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        )
    }
}
