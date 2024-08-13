//
//  Node.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


/// Async public methods use this global actor; it is therefore recommended to mark audio-related logic in your code with AudioActor.
@globalActor
actor AudioActor {
	static var shared = AudioActor()
}


@usableFromInline let audioSem: DispatchSemaphore = .init(value: 1)

@inlinable func withAudioLock<T>(execute: () -> T) -> T {
	audioSem.wait()
	defer {
		audioSem.signal()
	}
	return execute()
}


// NB: names that start with an underscore are executed or accessed on the system audio thread. Names that end with $ should be called only within a semaphore lock, i.e. withAudioLock { }


struct StreamFormat: Equatable {
	let sampleRate: Double
	let bufferFrameSize: Int
	let isStereo: Bool

	var transitionFrames: Int { min(bufferFrameSize, Int(sampleRate) / 100) } // ~10ms

	static var `default`: Self { .init(sampleRate: 48000, bufferFrameSize: 512, isStereo: true) }
}


// MARK: - Node

/// Generic abstract audio node; all other generator and filter types are subclasses of `Node`. All public methods are thread-safe.
class Node: @unchecked Sendable {

	init(isEnabled: Bool = true) {
		_prevEnabled = isEnabled
		_config = .init(enabled: isEnabled)
		config$ = .init(enabled: isEnabled)
	}

	/// Indicates whether rendering should be skipped; if the node is disabled, buffers are filled with silence and the input renderer is not called. The last cycle after disabling the node is spent on gracefully ramping down the audio data; similarly the first cycle after enabling gracefully ramps up the data
	var isEnabled: Bool {
		get { withAudioLock { config$.enabled } }
		set { withAudioLock { config$.enabled = newValue } }
	}

	/// Unlike isEnabled, isMuted always calls the rendering routines but ignores the data and fills buffers with silence if set to true; like with isEnabled ramping can take place when changing this property
	var isMuted: Bool {
		get { withAudioLock { config$.muted } }
		set { withAudioLock { config$.muted = newValue } }
	}

	/// Indicates whether custom rendering routine should be called or not; useful for filters or effect type nodes; note that no ramping takes place when changing this property
	var isBypassing: Bool {
		get { withAudioLock { config$.bypass } }
		set { withAudioLock { config$.bypass = newValue } }
	}

	///Returns the stream format known to this node; nodes receive this data when they connect to other nodes and the stream format is known to any one of them in the chain.
	var format: StreamFormat? {
		withAudioLock { config$.format }
	}

	/// Connects a node that should provide source data. Each node should be connected to only one other node at a time. This is a fast synchronous version for connecting nodes that aren't yet rendering, i.e. no need to smoothen the edge. See also `smoothConnect()`.
	func connect(_ input: Node) {
		withAudioLock {
			config$.format.map { input.updateFormat$($0) }
			config$.input = input
		}
	}

	/// Disconnects input.
	func disconnect() {
		withAudioLock {
			config$.input = nil
		}
	}

	/// Connects input smoothly, i.e. ensuring no clicks happen. Use this method when connecting nodes while already running and rendering audio.
	@AudioActor
	func smoothConnect(_ input: Node) async {
		let wasMuted = isMuted
		isMuted = true
		connect(input)
		await Sleep(approximateCycleDuration) // the simplest possible synrhonization method, we don't want to complicate things
		isMuted = wasMuted
	}

	/// Disconnects input smoothly, i.e. ensuring no clicks happen.
	@AudioActor
	func smoothDisconnect() async {
		let wasMuted = isMuted
		isMuted = true
		await Sleep(approximateCycleDuration)
		disconnect()
		isMuted = wasMuted
	}

	/// Connects a node that serves as an observer of audio data, i.e. a node whose `monitor(frameCount:buffers:)` method will be called with each cycle.
	func connectMonitor(_ monitor: Monitor) {
		withAudioLock {
			config$.format.map { monitor.updateFormat$($0) }
			config$.monitor = monitor
		}
	}

	/// Disconnects the monitor.
	func disconnectMonitor() {
		withAudioLock {
			config$.monitor = nil
		}
	}

	/// Returns approximate duration of a rendering cycle; useful when waiting for some parameter to take effect.
	var approximateCycleDuration: TimeInterval {
		withAudioLock {
			format$.map { Double($0.bufferFrameSize) / Double($0.sampleRate) + 0.001 } ?? 0
		}
	}

	/// Name of the node for debug printing
	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	deinit {
		DLOG("deinit \(debugName)")
	}


	// MARK: - Internal: rendering

	/// Abstract overridable function that's called if this node is enabled, not bypassing and is connected to another node is `input`. Subclasses either generate or mutate the sound in this routine.
	func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		Abstract()
	}


	final func _internalRender(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {

		// 1. Prepare the config
		withAudioLock {
			_willRender$()
		}

		// 2. Not enabled: ramp out or return silence
		if !_config.enabled {
			if _prevEnabled {
				_prevEnabled = false
				_reset()
				let status = _internalRender2(ramping: true, frameCount: frameCount, buffers: buffers)
				if status == noErr {
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: _transitionFrames, buffers: buffers)
				}
				return status
			}
			return FillSilence(frameCount: frameCount, buffers: buffers)
		}

		// 3. Enabled: ramp in if needed
		if !_prevEnabled {
			_prevEnabled = true
			let status = _internalRender2(ramping: true, frameCount: frameCount, buffers: buffers)
			if status == noErr {
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionFrames, buffers: buffers)
			}
			return status
		}

		// 4. No ramps, fully enabled: pass on to check the mute status
		return _internalRender2(ramping: false, frameCount: frameCount, buffers: buffers)
	}


	private func _internalRender2(ramping: Bool, frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var status: OSStatus = noErr

		// 5. Pull input data
		if let input = _config.input {
			status = input._internalRender(frameCount: frameCount, buffers: buffers)
		}

		// 6. Call the abstract render routine for this node
		if status == noErr {
			if !_config.bypass {
				status = _render(frameCount: frameCount, buffers: buffers)
			}
			else if _config.input == nil {
				// Bypassing and no input specified, fill with silence. If this node is also muted, silence will be filled twice but we are fine with it, don't want to complicate this function any further.
				FillSilence(frameCount: frameCount, buffers: buffers)
			}
		}

		// 7. Playing muted: keep generating and replacing with silence; the first buffer is smoothened
		if _config.muted {
			if !_prevMuted {
				_prevMuted = true
				if !ramping {
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: _transitionFrames, buffers: buffers)
					return _internalMonitor(status: status, frameCount: frameCount, buffers: buffers)
				}
			}
			FillSilence(frameCount: frameCount, buffers: buffers)
			return _internalMonitor(status: status, frameCount: frameCount, buffers: buffers)
		}

		// 8. Not muted; ensure switching to unmuted state is smooth too
		if _prevMuted {
			_prevMuted = false
			if !ramping {
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionFrames, buffers: buffers)
			}
		}

		// 9. Notify the monitor (tap) node if there's any
		return _internalMonitor(status: status, frameCount: frameCount, buffers: buffers)
	}


	private func _internalMonitor(status: OSStatus, frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		if status == noErr, let monitor = _config.monitor {
			// Call monitor only if there's actual data generated. This helps monitors like file writers only receive actual data, not e.g. silence that can occur due to timing issues with the microphone. This however leaves the monitor unaware of any gaps which may not be good for e.g. meter UI elements. Should find a way to handle these situations.
			monitor._internalRender(frameCount: frameCount, buffers: buffers)
		}
		return status
	}


	func _willRender$() {
		_config = config$
	}


	func _reset() {
		_prevEnabled = _config.enabled
		_prevMuted = _config.muted
		_config.input?._reset()
	}


	// MARK: - Internal: Connection management

	/// Called by the node requesting connection with this node, or otherwise when propagating a new format down the chain; overridable. The audio semaphore is in a locked state which means all methods and properties with the $ suffix can be used here.
	func updateFormat$(_ format: StreamFormat) {
		DLOG("\(debugName).didConnect(\(format.sampleRate), \(format.bufferFrameSize), \(format.isStereo ? "stereo" : "mono"))")
		if format != config$.format {
			// This is where a known format is propagated down the chain
			config$.input?.updateFormat$(format)
			config$.monitor?.updateFormat$(format)
			config$.format = format
		}
	}


	var _transitionFrames: Int { _config.format?.transitionFrames ?? 0 }
	var _isInputConnected: Bool { _config.input != nil }
	var _isEnabled: Bool { _config.enabled }
	var format$: StreamFormat? { config$.format }


	// MARK: - Private

	private struct Config {
		var format: StreamFormat?
		var monitor: Monitor?
		var input: Node?
		var enabled: Bool
		var muted: Bool = false
		var bypass: Bool = false
	}

	private var config$: Config // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config // config used during the rendering cycle
	private var _prevEnabled: Bool
	private var _prevMuted: Bool = false
}
