//
//  Node.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


@globalActor
actor AudioActor {
	static var shared = AudioActor()
}


@usableFromInline let audioSem: DispatchSemaphore = .init(value: 1)

@inlinable func withAudioLock<T>(execute: () -> T) -> T {
	audioSem.wait()
	defer { audioSem.signal() }
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

class Node {

	// MARK: - Public interface

	var isEnabled: Bool {
		get { withAudioLock { config$.enabled } }
		set { withAudioLock { config$.enabled = newValue } }
	}


	var isMuted: Bool {
		get { withAudioLock { config$.muted } }
		set { withAudioLock { config$.muted = newValue } }
	}


	var format: StreamFormat? {
		withAudioLock { config$.format }
	}


	func connect(_ input: Node) {
		withAudioLock {
			config$.format.map { input.willConnect$(with: $0) }
			config$.input = input
		}
	}


	func disconnect() {
		withAudioLock {
			config$.input?.didDisconnect$()
			config$.input = nil
		}
	}


	func connectMonitor(_ monitor: Node) {
		withAudioLock {
			config$.format.map { monitor.willConnect$(with: $0) }
			config$.monitor = monitor
		}
	}


	func disconnectMonitor() { 
		withAudioLock {
			config$.monitor?.didDisconnect$()
			config$.monitor = nil
		}
	}


	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	// MARK: - Internal: rendering

	// Overridable function, should be chain-called from subclasses to ensure the connected input generates its sound
	func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		if let input = _config.input {
			return input._internalRender(frameCount: frameCount, buffers: buffers)
		}
		return FillSilence(frameCount: frameCount, buffers: buffers)
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

		// 5. Generate data; redefined in subclasses
		let status = _render(frameCount: frameCount, buffers: buffers)

		// 6. Playing muted: keep generating and replacing with silence; the first buffer is smoothened
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

		// 7. Not muted; ensure switching to unmuted state is smooth too
		if _prevMuted {
			_prevMuted = false
			if !ramping {
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionFrames, buffers: buffers)
			}
		}

		// 8. Notify the monitor (tap) node if there's any
		return _internalMonitor(status: status, frameCount: frameCount, buffers: buffers)
	}


	private func _internalMonitor(status: OSStatus, frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		if status == noErr {
			// Call monitor only if there's actual data generated. This helps monitors like file writers only receive actual data, not e.g. silence that can occur due to timing issues with the microphone. This however leaves the monitor unaware of any gaps which may not be good for e.g. meter UI elements. Should find a way to handle these situations.
			_ = _config.monitor?._internalRender(frameCount: frameCount, buffers: buffers)
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
		_config.monitor?._reset()
	}


	// MARK: - Internal: Connection management

	private(set) var isConnected: Bool = false // there is an incoming connection to this node


	// Called by the node requesting connection with this node, or otherwise when propagating a new format down the chain
	func willConnect$(with format: StreamFormat) {
		Assert(!isConnected, 51030)
		DLOG("\(debugName).didConnect(\(format.sampleRate), \(format.bufferFrameSize), \(format.isStereo ? "stereo" : "mono"))")
		if format != config$.format {
			// This is where a known format is propagated down the chain
			config$.input?.updateFormat$(with: format)
			config$.monitor?.updateFormat$(with: format)
			config$.format = format
		}
		isConnected = true
	}


	// Called by the node requesting disconnection from this node
	func didDisconnect$() {
		Assert(isConnected, 51031)
		DLOG("\(debugName).didDisconnect()")
		isConnected = false
		config$.format = nil
	}


	var _transitionFrames: Int { _config.format?.transitionFrames ?? 0 }


	// MARK: - Private

	private struct Config {
		var format: StreamFormat?
		var monitor: Node?
		var input: Node?
		var enabled: Bool = true
		var muted: Bool = false
	}


	// Called internally from the node that requests connection and if the format is known and different from the previous one
	private func updateFormat$(with format: StreamFormat) {
		didDisconnect$()
		willConnect$(with: format)
	}


	private var config$: Config = .init() // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config = .init() // config used during the rendering cycle
	private var _prevEnabled = true
	private var _prevMuted = false
}


// MARK: - Filter

class Filter: Node {

	var bypass: Bool {
		get { withAudioLock { bypass$ } }
		set { withAudioLock { bypass$ = newValue } }
	}


	func _filter(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		Abstract()
	}


	final override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		let status = super._render(frameCount: frameCount, buffers: buffers)
		if bypass || status != noErr {
			return status
		}
		return _filter(frameCount: frameCount, buffers: buffers)
	}


	override func _willRender$() {
		super._willRender$()
		_bypass = bypass$
	}


	private var bypass$: Bool = false
	private var _bypass: Bool = false
}
