//
//  Node.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


public struct StreamFormat: Equatable {
	public let sampleRate: Double
	public let isStereo: Bool

	public static var `default`: Self { .init(sampleRate: 48000, isStereo: true) }
	public static var defaultMono: Self { .init(sampleRate: 48000, isStereo: false) }
}


// MARK: - Node

// NB: names that start with an underscore are executed or accessed on the system audio thread. Names that end with $ should be called only within a semaphore lock, i.e. withAudioLock { }


public class Node: @unchecked Sendable {

	@inlinable
	public func withAudioLock<T>(execute: () -> T) -> T {
		audioSem.wait()
		defer {
			audioSem.signal()
		}
		return execute()
	}

	/// Name of the node for debug printing
	var debugName: String { String(describing: self).components(separatedBy: ".").last! }

	deinit {
		DLOG("deinit \(debugName)")
	}

	public let audioSem: DispatchSemaphore = .init(value: 1)
}


// MARK: - Source

/// Generic abstract audio node; all other generator and filter types are subclasses of `Node`. All public methods are thread-safe.
public class Source: Node, @unchecked Sendable {

	init(isEnabled: Bool = true) {
		_prevEnabled = isEnabled
		_config = .init(enabled: isEnabled)
		config$ = .init(enabled: isEnabled)
	}

	/// Indicates whether rendering should be skipped; if the node is disabled, buffers are filled with silence and the input renderer is not called. The last cycle after disabling the node is spent on gracefully ramping down the audio data; similarly the first cycle after enabling gracefully ramps up the data
	public var isEnabled: Bool {
		get { withAudioLock { config$.enabled } }
		set { withAudioLock { config$.enabled = newValue } }
	}

	/// Indicates whether custom rendering routine should be called or not; useful for filters or effect type nodes; note that no ramping takes place when changing this property
	public var isBypassing: Bool {
		get { withAudioLock { config$.bypass } }
		set { withAudioLock { config$.bypass = newValue } }
	}

	/// Connects a node that should provide source data. Each node should be connected to only one other node at a time. This is a fast synchronous version for connecting nodes that aren't yet rendering, i.e. no need to smoothen the edge.
	@discardableResult
	public func connectSource<S: Source>(_ source: S) -> S {
		withAudioLock {
			config$.source = source
		}
		return source
	}

	/// Disconnects input. See also `smoothDisconnect()`.
	public func disconnectSource() {
		withAudioLock {
			config$.source = nil
		}
	}

	/// Disconnects input smoothly, i.e. ensuring no clicks happen.
	public func smoothDisconnect() async {
		let wasEnabled = isEnabled
		isEnabled = false
		await Sleep(0.02) // this is not precise, what to do?
		disconnectSource()
		isEnabled = wasEnabled
	}

	/// Connects a node that serves as an observer of audio data, i.e. a node whose `monitor(frameCount:buffers:)` method will be called with each cycle.
	@discardableResult
	public func connectMonitor<M: Monitor>(_ monitor: M) -> M {
		withAudioLock {
			config$.monitor = monitor
		}
		return monitor
	}

	/// Disconnects the monitor.
	public func disconnectMonitor() {
		withAudioLock {
			config$.monitor = nil
		}
	}


	// MARK: - Internal: rendering

	/// Abstract overridable function that's called if this node is enabled, not bypassing and is connected to another node as `source`. Subclasses either generate or mutate the sound in this routine.
	func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		Abstract()
	}


	// Called from the system output callback
	final func _internalPull(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {

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
					Smooth(out: true, frameCount: frameCount, fadeFrameCount: transitionFrames(frameCount), buffers: buffers)
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
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: transitionFrames(frameCount), buffers: buffers)
			}
			return status
		}

		// 4. No ramps, fully enabled: pass on to the rendering method
		return _internalRender2(ramping: false, frameCount: frameCount, buffers: buffers)
	}


	private func _internalRender2(ramping: Bool, frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var status: OSStatus = noErr

		// 5. Pull input data
		if let input = _config.source {
			status = input._internalPull(frameCount: frameCount, buffers: buffers)
		}

		// 6. Call the abstract render routine for this node
		if status == noErr {
			if !_config.bypass {
				status = _render(frameCount: frameCount, buffers: buffers)
			}
			else if _config.source == nil {
				// Bypassing and no source specified, fill with silence.
				FillSilence(frameCount: frameCount, buffers: buffers)
			}
		}

		// 7. Notify the monitor (tap) node if there's any
		if status == noErr, let monitor = _config.monitor {
			// Call monitor only if there's actual data generated. This helps monitors like file writers only receive actual data, not e.g. silence that can occur due to timing issues with the microphone. This however leaves the monitor unaware of any gaps which may not be good for e.g. meter UI elements. Should find a way to handle these situations.
			_ = monitor._internalMonitor(frameCount: frameCount, buffers: buffers)
			return noErr
		}
		return status
	}


	func _willRender$() {
		_config = config$
	}


	func _reset() {
		_prevEnabled = _config.enabled
		_config.source?._reset()
	}


	// MARK: - Internal: Connection management

	final var _isInputConnected: Bool { _config.source != nil }
	final var _isEnabled: Bool { _config.enabled }


	// MARK: - Private

	private struct Config {
		var monitor: Monitor?
		var source: Source?
		var enabled: Bool
		var bypass: Bool = false
	}

	private var config$: Config // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config // config used during the rendering cycle
	private var _prevEnabled: Bool
}
