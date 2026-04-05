//
//  Converter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 08.03.26.
//

import Foundation
import AVFoundation


/// Converts audio from `sourceFormat` to `targetFormat` using `AVAudioConverter`, handling both sample rate conversion and mono↔stereo channel mapping. Not thread-safe; call from the audio thread only.
public final class Converter {

	public let sourceFormat: StreamFormat
	public let targetFormat: StreamFormat

	public init(sourceFormat: StreamFormat, targetFormat: StreamFormat) {
		self.sourceFormat = sourceFormat
		self.targetFormat = targetFormat

		let srcAV = AVAudioFormat(standardFormatWithSampleRate: sourceFormat.sampleRate, channels: AVAudioChannelCount(sourceFormat.numChannels))!
		let dstAV = AVAudioFormat(standardFormatWithSampleRate: targetFormat.sampleRate, channels: AVAudioChannelCount(targetFormat.numChannels))!

		converter = AVAudioConverter(from: srcAV, to: dstAV)!
		feedBuffer = AVAudioPCMBuffer(pcmFormat: srcAV, frameCapacity: Self.maxFrames)!
		let outputCapacity = AVAudioFrameCount(ceil(Double(Self.maxFrames) * targetFormat.sampleRate / sourceFormat.sampleRate)) + 1
		outputBuffer = AVAudioPCMBuffer(pcmFormat: dstAV, frameCapacity: outputCapacity)!
	}

	/// Converts `frameCount` frames from `buffers` (in `sourceFormat`) and returns the output frame count and buffer list.
	/// The returned `AudioBufferListPtr` is backed by an internal buffer valid until the next call.
	public func convert(frameCount: Int, buffers: AudioBufferListPtr) -> (frames: Int, buffers: AudioBufferListPtr) {
		assert(frameCount <= Self.maxFrames)

		outputBuffer.frameLength = AVAudioFrameCount(ceil(Double(frameCount) * targetFormat.sampleRate / sourceFormat.sampleRate))
		var offset = 0
		var error: NSError?
		_ = converter.convert(to: outputBuffer, error: &error) { inFrames, outStatus in
			let toCopy = min(frameCount - offset, Int(inFrames))
			if toCopy <= 0 {
				outStatus.pointee = .noDataNow
				return nil
			}
			let feedChannels = self.feedBuffer.floatChannelData!
			for i in 0..<self.sourceFormat.numChannels {
				memcpy(feedChannels[i], buffers[i].mData!.advanced(by: offset * SizeOfSample), toCopy * SizeOfSample)
			}
			self.feedBuffer.frameLength = AVAudioFrameCount(toCopy)
			offset += toCopy
			outStatus.pointee = .haveData
			return self.feedBuffer
		}
		return (Int(outputBuffer.frameLength), AudioBufferListPtr(outputBuffer.mutableAudioBufferList))
	}

	/// Resets the converter's internal state. Call on stream discontinuities (e.g. after the node is re-enabled).
	public func reset() {
		converter.reset()
	}


	// Private

	private static let maxFrames: AVAudioFrameCount = 4096

	private let converter: AVAudioConverter
	private let feedBuffer: AVAudioPCMBuffer    // chunk fed to the converter per callback
	private let outputBuffer: AVAudioPCMBuffer  // converter output (targetFormat)
}
