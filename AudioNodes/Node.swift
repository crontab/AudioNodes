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


struct Connector {
	private(set) var format: StreamFormat?
	private(set) var input: Node?


	mutating func setFormatSafe(_ newFormat: StreamFormat) {
		if let input, newFormat != format {
			input.didDisconnectSafe()
			input.willConnectSafe(with: newFormat)
		}
		format = newFormat
	}


	mutating func connectSafe(_ newInput: Node) {
		Assert(!newInput.isConnected, 51030)
		if let format {
			newInput.willConnectSafe(with: format)
		}
		input = newInput
	}


	mutating func disconnectSafe() {
		defer {
			input?.didDisconnectSafe()
		}
		input = nil
	}


	mutating func resetFormat() {
		format = nil
	}
}


// MARK: - Node

class Node {

	var isEnabled: Bool {
		get { withAudioLock { _userConfig.enabled } }
		set { withAudioLock { _userConfig.enabled = newValue } }
	}


	var isMuted: Bool {
		get { withAudioLock { _userConfig.muted } }
		set { withAudioLock { _userConfig.muted = newValue } }
	}


	func connectMonitor(_ input: Node) { withAudioLock { _userConfig.monitor.connectSafe(input) } }

	func disconnectMonitor() { withAudioLock { _userConfig.monitor.disconnectSafe() } }

	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	// Internal

	private(set) var isConnected: Bool = false


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

		// 4. Generate data; redefined in subclasses
		let status = _render(frameCount: frameCount, buffers: buffers)

		// 5. Playing muted: keep generating and replacing with silence; the first buffer is smoothened
		if _config.muted {
			if !_prevMuted {
				_prevMuted = true
				if !ramping {
					// TODO: should probably also pass this to the monitor
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
					return status
				}
			}
			FillSilence(frameCount: frameCount, buffers: buffers)
			return status
		}

		// 6. Not muted; ensure switching to unmuted state is smooth too
		if _prevMuted {
			_prevMuted = false
			if !ramping {
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: _transitionSamples, buffers: buffers)
			}
		}

		// 7. Notify the monitor (tap) node if there's any
		if status == noErr {
			// Call monitor only if there's actual data generated. This helps monitors like file writers only receive actual data, not e.g. silence that can occur due to timing issues with the microphone. This however leaves the monitor unaware of any gaps which may not be good for e.g. meter UI elements. Should find a way to handle these situations.
			_ = _config.monitor.input?._internalRender(frameCount: frameCount, buffers: buffers)
		}

		// 8. Done
		return status
	}


	func _willRenderSafe() {
		_config = _userConfig
	}


	func _reset() {
		_prevEnabled = _config.enabled
		_prevMuted = _config.muted
		_config.monitor.input?._reset()
	}


	func willConnectSafe(with format: StreamFormat) {
		DLOG("\(debugName).didConnect(\(format.sampleRate), \(format.bufferFrameSize), \(format.isStereo ? "stereo" : "mono"))")
		isConnected = true
		_userConfig.monitor.setFormatSafe(format)
	}


	func didDisconnectSafe() {
		DLOG("\(debugName).didDisconnect()")
		isConnected = false
		_userConfig.monitor.resetFormat()
	}


	var _transitionSamples: Int { _config.monitor.format?.transitionSamples ?? 0 }


	// Private

	private struct Config {
		var monitor = Connector() // used for storing the format regardless of whether there's a monitor connected or not
		var enabled: Bool = true
		var muted: Bool = false
	}

	private var _userConfig: Config = .init()
	private var _config: Config = .init()
	private var _prevEnabled = true
	private var _prevMuted = false
}
