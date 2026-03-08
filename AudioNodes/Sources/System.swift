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

/// High quality system audio I/O node. You can create multiple system nodes, e.g. if you want to have stereo and mono I/O separately. Normally you create a graph of nodes and connect it to system output for playing audio; recording is done using the `input` node.
public final class Stereo: System, @unchecked Sendable {

	public init() {
		super.init(isStereo: true)
	}

#if os(iOS)
	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_RemoteIO }
#else
	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_DefaultOutput }
#endif
}


// MARK: - Mono

/// Mono system I/O with optional voice processing (echo cancellation, AGC). On iOS uses VoiceProcessingIO when options are used; on macOS uses default output and options are ignored.
public final class Mono: System, @unchecked Sendable {

	public init(echoCancellation: Bool = true, agc: Bool = false) {
		super.init(isStereo: false)
		var bypass: UInt32 = echoCancellation ? 0 : 1
		NotError(AudioUnitSetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 1, &bypass, SizeOf(bypass)), 51025)
		var enableAGC: UInt32 = agc ? 1 : 0
		NotError(AudioUnitSetProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 1, &enableAGC, SizeOf(enableAGC)), 51026)
	}

	fileprivate override class func subtype() -> UInt32 { kAudioUnitSubType_VoiceProcessingIO }
}


// MARK: - System

open class System: Source, @unchecked Sendable {

	/// System input node for recording; nil until `requestInputAuthorization()` is called and permission is granted; stays nil if there are no input devices.
	public private(set) var input: Input?

	/// System stream format.
	public final let outputFormat: StreamFormat
	public final let inputFormat: StreamFormat

	/// Indicates whether the audio system is enabled and is rendering data.
	public var isRunning: Bool {
		var flag: UInt32 = 0, flagSize = SizeOf(flag)
		NotError(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &flag, &flagSize), 51028)
		return flag != 0
	}


	/// Starts the audio system.
	public func start() {
		if !isRunning {
			NotError(AudioUnitInitialize(unit), 51007)
			NotError(AudioOutputUnitStart(unit), 51009)
			DLOG("\(debugName).start()")
		}
	}


	/// Stops the audio system. To avoid clicks, disconnect the input using `smoothDisconnect() async` prior to calling `stop()`.
	public func stop() {
		AudioOutputUnitStop(unit)
		AudioUnitUninitialize(unit)
		DLOG("\(debugName).stop()")
	}


	/// Requests authorization for audio input on platforms where it's required, and initializes the `input` property.
	public func requestInputAuthorization() async -> Bool {
		guard input == nil else { return true }

		switch AVCaptureDevice.authorizationStatus(for: .audio) {
			case .authorized: // The user has previously granted access
				input = Input(system: self)
				return true

			case .notDetermined: // The user has not yet been asked for access
				let granted = await AVCaptureDevice.requestAccess(for: .audio)
				if granted, input == nil {
					input = Input(system: self)
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
	public static var inputAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }


	/// Creates a system I/O node.
	fileprivate init(isStereo: Bool) {
		var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: Self.subtype(), componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
		let comp = AudioComponentFindNext(nil, &desc)!
		var tempUnit: AudioUnit?
		NotError(AudioComponentInstanceNew(comp, &tempUnit), 51000)
		unit = tempUnit!

		// Determine optimal output sample rate
		var descr = AudioStreamBasicDescription()
		var descrSize = SizeOf(descr)
		NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &descr, &descrSize), 51005)
		let sampleRate = descr.mSampleRate > 0 ? descr.mSampleRate : Self.hardwareSampleRate(unit)

		// Read hardware format, make sure it's non-empty
		var inDescr = AudioStreamBasicDescription(), inDescrSize = SizeOf(inDescr)
		let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &inDescr, &inDescrSize)
		if status != noErr || inDescr.mChannelsPerFrame == 0 {
			print("AudioNodes: audio is not available on this system")
			outputFormat = .default
			inputFormat = .default
			super.init()
			isEnabled = false
			return
		}

		outputFormat = .init(sampleRate: sampleRate, isStereo: isStereo)
		inputFormat = .init(sampleRate: sampleRate, isStereo: isStereo)

		super.init()

		// Now set our format parameters using the same sampling rate
		descr = AudioStreamBasicDescription.canonical(with: .init(sampleRate: sampleRate, isStereo: isStereo))
		descrSize = SizeOf(descr)
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &descr, descrSize), 51006)

		// Set up the render callback
		var callback = AURenderCallbackStruct(inputProc: outputRenderCallback, inputProcRefCon: Bridge(obj: self))
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, SizeOf(callback)), 51004)

		DLOG("\(debugName).streamFormat: sampleRate=\(outputFormat.sampleRate), isStereo=\(outputFormat.isStereo)")
	}


	deinit {
		stop()
		AudioComponentInstanceDispose(unit)
	}


	public static var version: String? { Bundle(for: System.self).infoDictionary?["CFBundleShortVersionString"] as? String }


	// MARK: - Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
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


	// MARK: - Input

	public final class Input: Monitor, @unchecked Sendable {

		// Input is a special node that's not a real source; it can only be monitored by connecting a Monitor object, possibly chained

		fileprivate final var renderBuffer: AudioBufferListPtr

		// On iOS and also macOS Mono mode `unit` is shared with the output unit; for macOS Stereo it's a dedicated input-only AUHAL unit
		fileprivate final var unit: AudioUnit
		private weak var system: System?


		fileprivate init?(system: System) {
			self.unit = system.unit
			self.system = system

#if os(macOS)
			// On macOS, use a dedicated input-only AUHAL unit. This avoids the device conflict that
			// arises from sharing a single unit for both input and output when they use different devices.
			var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
			let comp = AudioComponentFindNext(nil, &desc)!
			var tempUnit: AudioUnit?
			NotError(AudioComponentInstanceNew(comp, &tempUnit), 51029)
			unit = tempUnit!

			// Input-only: disable output bus, enable input bus
			var zero: UInt32 = 0, one: UInt32 = 1
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &zero, SizeOf(zero)), 51030)
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, SizeOf(one)), 51031)

			// Point to the system default input device
			var deviceID = AudioDeviceID(kAudioObjectUnknown)
			var propSize = SizeOf(deviceID)
			var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
			AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID)
			guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, SizeOf(deviceID)), 51032)
#endif

			// Read hardware format, make sure it's non-empty
			var inDescr = AudioStreamBasicDescription(), inDescrSize = SizeOf(inDescr)
			let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &inDescr, &inDescrSize)
			if status != noErr || inDescr.mChannelsPerFrame == 0 {
				return nil
			}

			// Set the "soft" format for audio input to make sure the sample rate is the same as for audio output
			if system.inputFormat.numChannels > inDescr.mChannelsPerFrame {
				var descr = AudioStreamBasicDescription.canonical(with: system.inputFormat)
				NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &descr, SizeOf(descr)), 51022)
			}

			// Render buffer: the input AU will allocate the data buffers, we just supply the buffer headers
			renderBuffer = AudioBufferList.allocate(maximumBuffers: system.inputFormat.numChannels)

			super.init()

			// Set render callback
			var callback = AURenderCallbackStruct(inputProc: inputRenderCallback, inputProcRefCon: Bridge(obj: self))
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Output, 1, &callback, SizeOf(callback)), 51008)

#if os(macOS)
			// Initialize now; isEnabled will just start/stop the already-initialized unit
			NotError(AudioUnitInitialize(unit), 51033)
#endif

			// Input is disabled by default, so set the internal var:
			super.isEnabled = false
		}


		deinit {
#if os(macOS)
			AudioOutputUnitStop(unit)
			AudioUnitUninitialize(unit)
			AudioComponentInstanceDispose(unit)
#endif
			renderBuffer.unsafeMutablePointer.deallocate()
		}


		public override var isEnabled: Bool {
			didSet {
				guard oldValue != isEnabled else {
					return
				}
#if os(macOS)
				if isEnabled {
					NotError(AudioOutputUnitStart(unit), 51034)
				}
				else {
					AudioOutputUnitStop(unit)
				}
#else
				// EnableIO cannot be changed on an initialized unit; stop/deinitialize first, then restore
				let prevRunning = system?.isRunning ?? false
				if prevRunning { system?.stop() }
				var enable: UInt32 = isEnabled ? 1 : 0
				NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, SizeOf(enable)), 51021)
				if prevRunning { system?.start() }
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

#if DEBUG
nonisolated(unsafe)
var lastFrameCount: UInt32 = 0
#endif

private func outputRenderCallback(userData: UnsafeMutableRawPointer, actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32, buffers: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

#if DEBUG_off
	if frameCount != lastFrameCount {
		lastFrameCount = frameCount
		Task.detached {
			print("Output buffer size:", frameCount)
		}
	}
#endif

	let obj: System = Bridge(ptr: userData)
	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	var filled: Bool = false
	obj._internalPull(frameCount: Int(frameCount), buffers: AudioBufferListPtr(&buffers!.pointee), filled: &filled)
	Assert(filled, 51001)
	return noErr
}


private func inputRenderCallback(userData: UnsafeMutableRawPointer, actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32, buffers unused: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

	let obj: System.Input = Bridge(ptr: userData)

	guard obj.isEnabled else {
		return noErr
	}

	let renderBuffer = obj.renderBuffer
	for i in 0..<renderBuffer.count {
		renderBuffer[i].mDataByteSize = frameCount * UInt32(SizeOfSample)
		renderBuffer[i].mData = nil
	}

	NotError(AudioUnitRender(obj.unit, actionFlags, timeStamp, busNumber, frameCount, renderBuffer.unsafeMutablePointer), 51024)

	// Check the first two samples in the right channel to see if it's silence; duplicate the left channel if so.
	// Apparently this happens on iPhones but not on the Mac or even the iPhone simulator.
	if renderBuffer.count == 2, renderBuffer[1].samples[0] == 0, renderBuffer[1].samples[1] == 0 {
		memcpy(renderBuffer[1].mData, renderBuffer[0].mData, Int(renderBuffer[0].mDataByteSize))
	}

	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	obj._internalMonitor(frameCount: Int(frameCount), buffers: renderBuffer)
	return noErr
}
