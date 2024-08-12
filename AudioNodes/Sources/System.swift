//
//  System.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation
import AVFoundation
import AudioToolbox


// MARK: - System

final class System: Node {

	/// System input node for recording; nil until `requestInputAuthorization()` is called and permission is granted; stays nil if there are no input devices.
	private(set) var input: Input?

	/// System input stream format.
	final let systemFormat: StreamFormat


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


	func requestInputAuthorization() async -> Bool {
		guard input == nil else { return true }

		switch AVCaptureDevice.authorizationStatus(for: .audio) {
			case .authorized: // The user has previously granted access
				input = Input(instance: self)
				return true

			case .notDetermined: // The user has not yet been asked for access
				let granted = await AVCaptureDevice.requestAccess(for: .audio)
				if granted, input == nil {
					input = Input(instance: self)
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


	init(isStereo: Bool) {
		var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: Self.subtype(), componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
		let comp = AudioComponentFindNext(nil, &desc)!
		var tempUnit: AudioUnit?
		NotError(AudioComponentInstanceNew(comp, &tempUnit), 51000)
		unit = tempUnit!

		// Get output descr parameters
		var descr = AudioStreamBasicDescription()
		var descrSize = SizeOf(descr)
		NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &descr, &descrSize), 51005)

		if descr.mSampleRate == 0 {
			descr.mSampleRate = Self.hardwareSampleRate(unit: unit)
			precondition(descr.mSampleRate > 0)
		}

		// Limit output sample rate to 48kHz. There may be some crazy external DAC connected to the Mac, haven't tried though
		// descr.mSampleRate = min(descr.mSampleRate, 48000)

		// Read hardware format, make sure it's non-empty
		var inDescr = AudioStreamBasicDescription(), inDescrSize = SizeOf(inDescr)
		let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &inDescr, &inDescrSize)
		if status != noErr || inDescr.mChannelsPerFrame == 0 {
			print("AudioNodes: audio is not available on this system")
			systemFormat = .default
			super.init()
			isEnabled = false
			return
		}

		systemFormat = StreamFormat(sampleRate: descr.mSampleRate, bufferFrameSize: Self.outputBufferFrameSize(unit: unit), isStereo: isStereo)

		super.init()

		// Now set our format parameters using the same sampling rate
		descr = .canonical(isStereo: isStereo, sampleRate: descr.mSampleRate)
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &descr, descrSize), 51006)

		// Set up the render callback
		var callback = AURenderCallbackStruct(inputProc: outputRenderCallback, inputProcRefCon: Bridge(obj: self))
		NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, SizeOf(callback)), 51004)

		// Imitate connection since we know the format which will be propagated to the entire chain
		willConnect$(with: systemFormat)
	}


	deinit {
		stop()
	}


	// MARK: - Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		if !_isInputConnected {
			FillSilence(frameCount: frameCount, buffers: buffers)
		}
		return noErr
	}


	// MARK: - Private

	private let unit: AudioUnit


#if os(iOS)
	fileprivate class func subtype() -> UInt32 { kAudioUnitSubType_RemoteIO }
#else
	fileprivate class func subtype() -> UInt32 { kAudioUnitSubType_DefaultOutput }
#endif


	private static func hardwareSampleRate(unit: AudioUnit) -> Double {
#if os(iOS)
		return AVAudioSession.sharedInstance().sampleRate
#else
		var sampleRate: Float64 = 0
		var size: UInt32 = SizeOf(sampleRate)
		NotError(AudioUnitGetProperty(unit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Global, 0, &sampleRate, &size), 51013)
		return sampleRate
#endif
	}


	private static func outputBufferFrameSize(unit: AudioUnit) -> Int {
#if os(iOS)
		return Int(ceil(AVAudioSession.sharedInstance().ioBufferDuration * hardwareSampleRate(unit: unit)))
#else
		var bufferSize: UInt32 = 0
		var size: UInt32 = SizeOf(bufferSize)
		NotError(AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufferSize, &size), 51014)
		return Int(bufferSize)
#endif
	}


	// MARK: - Input

	final class Input: Node {

		// Input is a special node that's not a real source; it can only be monitored by connecting a Monitor object, possibly chained

		static let maxFramesPerSlice = 4096

		fileprivate final var renderBuffer: AudioBufferListPtr

		// The AudioUnit reference is passed via the initializer; note that in this module it's shared across input and output nodes for the same IO type, i.e. there's one unit instance for Input and Output.
		fileprivate final var unit: AudioUnit
		private weak var system: System?


		fileprivate init?(instance: System) {
			let isStereo = false

			self.unit = instance.unit
			self.system = instance

			// Render buffer: the input AU will allocate the data buffers, we just supply the buffer headers
			renderBuffer = AudioBufferList.allocate(maximumBuffers: isStereo ? 2 : 1)

			super.init()

			// Set maximum buffer size as recommended by Apple
			var maxFramesPerSlice = UInt32(Self.maxFramesPerSlice)
			NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 1, &maxFramesPerSlice, SizeOf(maxFramesPerSlice)), 51003)

			// Tell the unit to allocate buffers - this is the default and it doesn't work on macOS anyway, fails with -10877
			// var one: UInt32 = 1
			// NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, 1, &one, SizeOf(one)), 51002)

			// Read hardware format, make sure it's non-empty
			var inDescr = AudioStreamBasicDescription(), inDescrSize = SizeOf(inDescr)
			let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &inDescr, &inDescrSize)
			if status != noErr || inDescr.mChannelsPerFrame == 0 {
				return nil
			}

			// Set format and sample rate to the same as hardware output
			var descr = AudioStreamBasicDescription.canonical(isStereo: isStereo, sampleRate: System.hardwareSampleRate(unit: unit))
			NotError(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &descr, SizeOf(descr)), 51022)

			// Set render callback
			var callback = AURenderCallbackStruct(inputProc: inputRenderCallback, inputProcRefCon: Bridge(obj: self))
			NotError(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Output, 1, &callback, SizeOf(callback)), 51008)

			// Input is disabled by default, so set the internal var:
			isEnabled = false

			// Imitate connection to pass the stream format to monitors, in case Input acts only as a pusher, not a source; safe to call as this is a constructor
			super.willConnect$(with: StreamFormat(sampleRate: descr.mSampleRate, bufferFrameSize: Self.maxFramesPerSlice, isStereo: isStereo))
		}


		final override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
			// Already rendered by the system in inputRenderCallback()
			return noErr
		}


		override func willConnect$(with format: StreamFormat?) {
			// Input doesn't work as a source
			Unrecoverable(51015)
		}


		deinit {
			renderBuffer.unsafeMutablePointer.deallocate()
		}


		// We override isEnabled rather than use _reset() because start()/stop() should be invoked on the main thread
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
	}
}


// MARK: - System callbacks

private func outputRenderCallback(userData: UnsafeMutableRawPointer, actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>, busNumber: UInt32, frameCount: UInt32, buffers: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
	let obj: System = Bridge(ptr: userData)
	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	return obj._internalRender(frameCount: Int(frameCount), buffers: AudioBufferListPtr(&buffers!.pointee))
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

	// let time = UnsafeMutablePointer<AudioTimeStamp>(mutating: timeStamp)
	return obj._internalRender(frameCount: Int(frameCount), buffers: obj.renderBuffer)
}
