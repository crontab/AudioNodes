//
//  Utilities.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import Accelerate
import CoreAudio


public typealias Sample = Float32
public typealias AudioBufferListPtr = UnsafeMutableAudioBufferListPointer
public let SizeOfSample = MemoryLayout<Sample>.size


let MIN_LEVEL_DB: Sample = -90


// MARK: - Errors, debugging

enum AudioError: LocalizedError {
	case fileOpen

	var errorDescription: String? {
		switch self {
			case .fileOpen: "Could not open file"
		}
	}
}


@inlinable
internal func debugOnly(_ body: () -> Void) {
	assert({ body(); return true }())
}


@inlinable
internal func DLOG(_ s: String) {
	debugOnly { print(s) }
}


@usableFromInline
func Unrecoverable(_ code: Int) -> Never {
	preconditionFailure("Unrecoverable error \(code)")
}


@inlinable
func NotError(_ error: OSStatus, _ code: Int) {
	if error != noErr {
		DLOG("ERROR: OS status: \(error)")
		Unrecoverable(code)
	}
}


@inlinable
func Abstract(_ fn: String = #function) -> Never {
	DLOG("Abstract method called: \(fn)")
	Unrecoverable(52001)
}


@inlinable
func Assert(_ cond: Bool, _ code: Int) {
	// TODO: should this be DEBUG only?
	if !cond { Unrecoverable(code) }
}


// MARK: - Misc.

@inlinable
func Bridge<T: AnyObject>(obj: T) -> UnsafeMutableRawPointer {
	return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}


@inlinable
func Bridge<T: AnyObject>(ptr: UnsafeRawPointer) -> T {
	return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}


@inlinable
func SizeOf<T>(_ v: T) -> UInt32 {
	return UInt32(MemoryLayout.size(ofValue: v))
}


@inlinable
func Sleep(_ t: TimeInterval) async {
	try? await Task.sleep(for: .seconds(t))
}


extension Comparable {
	@inlinable
	func clamped(to limits: ClosedRange<Self>) -> Self { min(max(self, limits.lowerBound), limits.upperBound) }
}



// MARK: - Audio Utilities

@inlinable
func transitionFrames(_ frameCount: Int) -> Int { min(512, frameCount) }


extension AudioStreamBasicDescription {

	static func canonical(with format: StreamFormat) -> Self {
		.init(mSampleRate: format.sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, mBytesPerPacket: UInt32(SizeOfSample), mFramesPerPacket: 1, mBytesPerFrame: UInt32(SizeOfSample), mChannelsPerFrame: format.isStereo ? 2 : 1, mBitsPerChannel: UInt32(8 * SizeOfSample), mReserved: 0)
	}
}


@inlinable
func FactorFromGain(_ gain: Float32) -> Float32 {
	// The base formula is 10^(x / 20) where x ∈ -90..0dB. The value of -90dB is the 16-bit silence, i.e. value that's lower than 1 in 16-bit encoding. That's theoretically, but in practice instead of multiplying by 90/20 we do times 2. Sounds nicer. The below formula can lower the volume if `gain` ∈ 0..1, or amplify if it's greater than 1. In the negative space it does the same but also inverses the signal.
	gain == 0 ? 0 :
		gain < 0 ? -pow(10, (-gain - 1) * 2) :
			pow(10, (gain - 1) * 2)
}


@discardableResult
func FillSilence(frameCount: Int, buffers: AudioBufferListPtr, offset: Int = 0) -> OSStatus {
	precondition(offset <= frameCount)
	if offset < frameCount {
		for i in 0..<buffers.count {
			vDSP_vclr(buffers[i].samples + offset, 1, UInt(frameCount - offset))
		}
	}
	return noErr
}


@inlinable
func Copy(from: AudioBuffer, to: AudioBuffer, frameCount: Int) {
	memcpy(to.mData, from.mData, frameCount * SizeOfSample)
}


@discardableResult
func Copy(from: AudioBufferListPtr, to: AudioBufferListPtr, fromOffset: Int, toOffset: Int, framesMax: Int) -> Int {
	// The reason framesMax exists and is enforced is that buffers may be longer than the available data in buffers coming from the system, for some unknown reason.
	let toCopy = min(from[0].sampleCount - fromOffset, to[0].sampleCount - toOffset, framesMax)
	precondition(from.count > 0 && to.count > 0)
	precondition(toCopy >= 0)
	if toCopy > 0 {
		let common = min(to.count, from.count)

		// 1. Copy to common channels first
		for i in 0..<common {
			memcpy(to[i].samples + toOffset, from[i].samples + fromOffset, toCopy * SizeOfSample)
		}

		// 2. If theere's a channel number mismatch, fill the missing channels with the first channel from source (likely just mono-to-stereo)
		for i in common..<to.count {
			memcpy(to[i].samples + toOffset, from[0].samples + fromOffset, toCopy * SizeOfSample)
		}

		// 3. We don't do stere-to-mono at the moment
	}
	return toCopy
}


// Fast non-logarithmic fade in/out: used for muting/unmuting - it's why it's called Smooth() and not say Ramp()
@discardableResult
func Smooth(out: Bool, frameCount: Int, fadeFrameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
	// DLOG("SMOOTH \(out ? "out" : "in")")
	let fadeFrameCount = min(frameCount, fadeFrameCount)
	if fadeFrameCount > 0 {
		for i in 0..<buffers.count {
			let samples = buffers[i].samples
			for i in 0..<fadeFrameCount {
				let t = Sample(i) / Sample(fadeFrameCount)
				samples[i] *= out ? 1 - t : t
			}
		}
	}
	return out ? FillSilence(frameCount: frameCount, buffers: buffers, offset: fadeFrameCount) : noErr
}


extension AudioBuffer {

	func rmsDb() -> Sample {
		rmsDb(frameCount: sampleCount, offset: 0)
	}

	func rmsDb(frameCount: Int, offset: Int = 0) -> Sample {
		var rms: Sample = 0
		vDSP_rmsqv(samples + offset, 1, &rms, UInt(min(frameCount, sampleCount - offset)))
		return (rms == 0) ? MIN_LEVEL_DB : max(MIN_LEVEL_DB, 20 * log10(rms))
	}
}


extension AudioBuffer {

	@inlinable
	var samples: UnsafeMutablePointer<Sample> {
		mData!.assumingMemoryBound(to: Sample.self)
	}

	@inlinable
	var sampleCount: Int {
		get { Int(mDataByteSize) / SizeOfSample }
		set { mDataByteSize = UInt32(newValue * SizeOfSample) }
	}

	@inlinable
	mutating func allocate(capacity: Int) {
		precondition(capacity > 0)
		precondition(mData == nil)
		mNumberChannels = 1
		mDataByteSize = UInt32(capacity * SizeOfSample)
		mData = UnsafeMutableRawPointer(UnsafeMutableBufferPointer<Sample>.allocate(capacity: capacity).baseAddress)
	}

	@inlinable
	mutating func deallocate() {
		mData?.deallocate()
		mData = nil
	}
}


class SafeAudioBufferList {
	final let buffers: AudioBufferListPtr
	final let capacity: Int

	init(isStereo: Bool, capacity: Int) {
		buffers = AudioBufferList.allocate(maximumBuffers: isStereo ? 2 : 1)
		for i in 0..<buffers.count {
			buffers[i].allocate(capacity: capacity)
		}
		self.capacity = capacity
	}

	var frameCount: Int {
		get { buffers[0].sampleCount }
		set {
			precondition(newValue >= 0 && newValue <= capacity)
			for i in 0..<buffers.count {
				buffers[i].sampleCount = newValue
			}
		}
	}

	deinit {
		for i in 0..<buffers.count {
			buffers[i].deallocate()
		}
		buffers.unsafeMutablePointer.deallocate()
	}
}
