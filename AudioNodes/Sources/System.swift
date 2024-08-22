//
//  System.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation
import AVFoundation
import AudioToolbox


// MARK: - Stereo

/// High quality system audio I/O node. You can create multiple system nodes, e.g. if you want to have stereo and mono I/O separately. Normally you create a graph of nodes and connect it to system output for playing audio; recording is done using the `monoInput` node.
final class Stereo: System {

	override init(isStereo: Bool = true, sampleRate: Double = 0) {
		super.init(isStereo: isStereo, sampleRate: sampleRate)
	}

#if os(iOS)
	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_RemoteIO }
#else
	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_DefaultOutput }
#endif
}


// MARK: - Voice

/// Lower quality mono I/O with voice processing (echo cancellation and possibly automatic gain control; see `mode`).
final class Voice: System {

	enum Mode {
		case normal
		case voice
		case voiceAGC
	}

	var mode: Mode = .voice {
		didSet {
			// Bypass
			var flag: UInt32 = mode == .normal ? 1 : 0
			NotError(AudioUnitSetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &flag, SizeOf(flag)), 51025)

			// AGC
			flag = mode == .voiceAGC ? 1 : 0
			NotError(AudioUnitSetProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 1, &flag, SizeOf(flag)), 51026)
		}
	}

	init(sampleRate: Double = 0) {
		super.init(isStereo: false, sampleRate: sampleRate)
	}

	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_VoiceProcessingIO }
}


// MARK: - System

class System: Node {

	/// System input node for recording; nil until `requestInputAuthorization()` is called and permission is granted; stays nil if there are no input devices.
	private(set) var monoInput: MonoInput?

	/// System stream format.
	final let outputFormat: StreamFormat
	final let monoInputFormat: StreamFormat

	/// Indicates whether the audio system is enabled and is rendering data.
	var isRunning: Bool {
		var flag: UInt32 = 0, flagSize = SizeOf(flag)
		NotError(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &flag, &flagSize), 51028)
		return flag != 0
	}


	/// Starts the audio system.
	func start() {
		if !isRunning {
			NotError(AudioUnitInitialize(unit), 51007)
			NotError(AudioOutputUnitStart(unit), 51009)
			DLOG("\(debugName).start()")
		}
	}


	/// Stops the audio system. To avoid clicks, disconnect the input using `smoothDisconnect() async` prior to calling `stop()`.
	func stop() {
		AudioOutputUnitStop(unit)
		AudioUnitUninitialize(unit)
		DLOG("\(debugName).stop()")
	}


	/// Requests authorization for audio input on platforms where it's required, and initializes the `monoInput` property.
	func requestInputAuthorization() async -> Bool {
		guard monoInput == nil else { return true }

		switch AVCaptureDevice.authorizationStatus(for: .audio) {
			case .authorized: // The user has previously granted access
				monoInput = MonoInput(system: self)
				return true

			case .notDetermined: // The user has not yet been asked for access
				let granted = await AVCaptureDevice.requestAccess(for: .audio)
				if granted, monoInput == nil {
					monoInput = MonoInput(system: self)
				}
				return granted

			case .denied: // The user has previously denied access.
				return false

			case .restricted: // The user can't grant access due to restrictions.
				return false

			@unknown default:
				return false
		}
	}


	/// Returns current audio input authorization as Bool
	static var inputAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }


	/// Creates a system I/O node.
	fileprivate init(isStereo: Bool = true, sampleRate: Double = 0) {
		var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: Self.subtype(), componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
		let comp = AudioComponentFindNext(nil, &desc)!
		var tempUnit: AudioUnit?
		NotError(AudioComponentInstanceNew(comp, &tempUnit), 51000)
		unit = tempUnit!

		// Determine optimal output sample rate
		var setSampleRate: Double = sampleRate
		if setSampleRate == 0 {
			var descr = AudioStreamBasicDescription()
			var descrSize = SizeOf(descr)
			NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &descr, &descrSize), 51005)
			setSampleRate = descr.mSampleRate > 0 ? descr.mSampleRate : Self.hardwareSampleRate(unit)
		}

		// Limit output sample rate to 48kHz. There may be some crazy external DAC connected to the Mac, haven't tried though
		// setSampleRate = min(setSampleRate, 48000)

		// Read hardware format, make sure it's non-empty
		var inDescr = AudioStreamBasicDescription(), inDescrSize = SizeOf(inDescr)
		let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &inDescr, &inDescrSize)
		if status != noErr || inDescr.mChannelsPerFrame == 0 {
			print("AudioNodes: audio is not available on this system")
			outputFormat = .default
			monoInputFormat = .defaultMono
			super.init()
			isEnabled = false
			return
		}

		outputFormat = .init(sampleRate: setSampleRate, isStereo: isStereo)
		monoInputFormat = .init(sampleRate: setSampleRate, isStereo: false)

		super.init()

		// Now set our format parameters using the same sampling rate
		var descr = AudioStreamBasicDescription.canonical(with: .init(sampleRate: setSampleRate, isStereo: isStereo))
		let descrSize = SizeOf(descr)
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &descr, descrSize), 51006)

		// Set up the render callback
		var callback = AURenderCallbackStruct(inputProc: outputRenderCallback, inputProcRefCon: Bridge(obj: self))
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, SizeOf(callback)), 51004)

		DLOG("\(debugName).streamFormat: sampleRate=\(outputFormat.sampleRate), isStereo=\(outputFormat.isStereo)")
	}


	deinit {
		stop()
	}


	static var version: String? { Bundle(for: System.self).infoDictionary?["CFBundleShortVersionString"] as? String }


	// MARK: - Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		if !_isInputConnected {
			FillSilence(frameCount: frameCount, buffers: buffers)
		}
		return noErr
	}


	// MARK: - Private

	fileprivate final let unit: AudioUnit

	fileprivate class func subtype() -> UInt32 { Abstract() }


	private static func hardwareSampleRate(_ unit: AudioUnit) -> Double {
#if os(iOS)
		return AVAudioSession.sharedInstance().sampleRate
#else
		var sampleRate: Float64 = 0
		var size: UInt32 = SizeOf(sampleRate)
		NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Global, 0, &sampleRate, &size), 51013)
		return sampleRate
#endif
	}


	// MARK: - MonoInput

	final class MonoInput: Monitor {

		// MonoInput is a special node that's not a real source; it can only be monitored by connecting a Monitor object, possibly chained

		fileprivate final var renderBuffer: AudioBufferListPtr

		// The AudioUnit reference is passed via the initializer; note that in this module it's shared across input and output nodes for the same IO type, i.e. there's one unit instance for MonoInput and Output.
		fileprivate final var unit: AudioUnit
		private weak var system: System?


		fileprivate init?(system: System) {
			self.unit = system.unit
			self.system = system

			// Read hardware format, make sure it's non-empty
			var descr = AudioStreamBasicDescription(), descrSize = SizeOf(descr)
			let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &descr, &descrSize)
			if status != noErr || descr.mChannelsPerFrame == 0 {
				return nil
			}

			// Set the "soft" format for audio input to make sure the sample rate is the same as for audio output
			descr = .canonical(with: system.monoInputFormat)
			NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &descr, &descrSize), 51022)

			// Render buffer: the input AU will allocate the data buffers, we just supply the buffer headers
			renderBuffer = AudioBufferList.allocate(maximumBuffers: Int(descr.mChannelsPerFrame))

			super.init()

			// Set render callback
			var callback = AURenderCallbackStruct(inputProc: inputRenderCallback, inputProcRefCon: Bridge(obj: self))
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Output, 1, &callback, SizeOf(callback)), 51008)

			// Input is disabled by default, so set the internal var:
			super.isEnabled = false
		}


		deinit {
			renderBuffer.unsafeMutablePointer.deallocate()
		}


		override var isEnabled: Bool {
			didSet {
				guard oldValue != isEnabled else {
					return
				}
#if os(iOS)
				// The following is a workaround for an iOS issue when a AU can not be enabled or disabled after initializiation; therefore we stop/deinitialize it before the operation and then restore the state
				let prevRunning = system?.isRunning ?? false
				if prevRunning {
					system?.stop()
				}
#endif
				var enable: UInt32 = isEnabled ? 1 : 0
				NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, SizeOf(enable)), 51021)
#if os(iOS)
				if prevRunning {
					system?.start()
				}
#endif
			}
		}


		override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
			// do nothing, the data is received from the system
		}
	}
}


// MARK: - System callbacks

// Both input and output callbacks are called by th system on the same thread.

private func outputRenderCallback(userData: UnsafeMutableRawPointer, actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32, buffers: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
	let obj: System = Bridge(ptr: userData)
	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	return obj._internalPull(frameCount: Int(frameCount), buffers: AudioBufferListPtr(&buffers!.pointee))
}


#if DEBUG
nonisolated(unsafe)
var lastFrameCount: UInt32 = 0
#endif


private func inputRenderCallback(userData: UnsafeMutableRawPointer, actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32, buffers unused: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

	let obj: System.MonoInput = Bridge(ptr: userData)

	guard obj.isEnabled else {
		return noErr
	}

#if DEBUG
	if frameCount != lastFrameCount {
		lastFrameCount = frameCount
		Task.detached {
			print("Buffer size:", frameCount)
		}
	}
#endif

	let renderBuffer = obj.renderBuffer
	for i in 0..<renderBuffer.count {
		renderBuffer[i].mDataByteSize = frameCount * UInt32(SizeOfSample)
		renderBuffer[i].mData = nil
	}

	NotError(AudioUnitRender(obj.unit, actionFlags, timeStamp, busNumber, frameCount, renderBuffer.unsafeMutablePointer), 51024)

	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	return obj._internalMonitor(frameCount: Int(frameCount), buffers: obj.renderBuffer)
}
