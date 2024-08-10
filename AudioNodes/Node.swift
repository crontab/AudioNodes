//
//  Node.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


@globalActor
@available(*, unavailable) // unused
actor AudioActor {
	static var shared = AudioActor()
}


@usableFromInline let audioSem: DispatchSemaphore = .init(value: 1)

@inlinable func withAudioLock<T>(execute: () -> T) -> T {
	audioSem.wait()
	defer { audioSem.signal() }
	return execute()
}


// NB: names that start with an underscore are executed or accessed on the system audio thread. Names that end with *Safe should be called only within a semaphore lock, i.e. withAudioLock { }


struct StreamFormat: Equatable {
	let sampleRate: Double
	let bufferFrameSize: Int
	let isStereo: Bool

	var transitionSamples: Int { min(bufferFrameSize, Int(sampleRate) / 100) } // ~10ms
}


// MARK: - Node

class Node {

	// MARK: - Public interface

	var isEnabled: Bool {
		get { withAudioLock { configSafe.enabled } }
		set { withAudioLock { configSafe.enabled = newValue } }
	}


	var isMuted: Bool {
		get { withAudioLock { configSafe.muted } }
		set { withAudioLock { configSafe.muted = newValue } }
	}


	func connect(_ input: Node) {
		withAudioLock {
			input.willConnectSafe(with: configSafe.format)
			configSafe.input = input
		}
	}


	func disconnect() {
		withAudioLock {
			let input = configSafe.input
			configSafe.input = nil
			input?.didDisconnectSafe()
		}
	}


	func connectMonitor(_ monitor: Node) {
		withAudioLock {
			monitor.willConnectSafe(with: configSafe.format)
			configSafe.monitor = monitor
		}
	}


	func disconnectMonitor() { 
		withAudioLock {
			let monitor = configSafe.monitor
			configSafe.monitor = nil
			monitor?.didDisconnectSafe()
		}
	}


	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	// MARK: - Internal: rendering

	func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		Abstract()
	}


	final func _internalRender(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {

		// 1. Prepare the config
		withAudioLock {
			_willRenderSafe()
		}

		// 2. Not enabled: ramp out or return silence
		if !_config.enabled {
			if _prevEnabled {
				_prevEnabled = false
				_reset()
				let status = _internalRender2(ramping: true, frameCount: frameCount, buffers: buffers)
				if status == noErr {
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
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
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
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
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
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
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
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


	func _willRenderSafe() {
		_config = configSafe
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
	func willConnectSafe(with format: StreamFormat?) {
		Assert(!isConnected, 51030)
		if let format {
			DLOG("\(debugName).didConnect(\(format.sampleRate), \(format.bufferFrameSize), \(format.isStereo ? "stereo" : "mono"))")
			if format != configSafe.format {
				// This is where a known format is propagated down the chain
				configSafe.input?.updateFormatSafe(with: format)
				configSafe.monitor?.updateFormatSafe(with: format)
				configSafe.format = format
			}
		}
		else {
			DLOG("\(debugName).didConnect(<format unknown>)")
		}
		isConnected = true
	}


	// Called by the node requesting disconnection from this node
	func didDisconnectSafe() {
		Assert(isConnected, 51031)
		DLOG("\(debugName).didDisconnect()")
		isConnected = false
		if configSafe.monitor == nil, configSafe.input == nil {
			configSafe.format = nil
		}
	}


	var _transitionSamples: Int { _config.format?.transitionSamples ?? 0 }


	// MARK: - Private

	private struct Config {
		var format: StreamFormat?
		var monitor: Node?
		var input: Node?
		var enabled: Bool = true
		var muted: Bool = false
	}


	// Called internally from the node that requests connection and if the format is known and different from the previous one
	private func updateFormatSafe(with format: StreamFormat) {
		didDisconnectSafe()
		willConnectSafe(with: format)
	}


	private var configSafe: Config = .init() // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config = .init() // config used during the rendering cycle
	private var _prevEnabled = true
	private var _prevMuted = false
}
