//
//  Node.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


@frozen public struct StreamFormat: Equatable {
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
	var debugName: String { String(describing: type(of: self)) }

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

	/// Disconnects input smoothly, i.e. ensuring no clicks happen. This function requires the node to be connected to an active rendering chain, i.e. either System or OfflineProcessor.
	/// NOTE: this is an async function and is not reentrant, meaning for the duration of disconnection nothing else should be done on this node.
	public func disconnectSource() async {
		// 1. Check if source is connected
		guard withAudioLock(execute: { config$.source != nil }) else { return }

		// 2. Remember the enabled flag and reset it
		let wasEnabled = isEnabled
		isEnabled = false

		// 3. Post a callback and wait until completed
		await withCheckedContinuation { cont in
			withAudioLock {
				config$.disconnectSource = {
					cont.resume()
				}
			}
		}
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
	func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		Abstract()
	}


	// Called from the system output callback
	final func _internalPull(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {

		// 1. Prepare the config
		withAudioLock {
			_willRender$()
		}

		// 2. Not enabled: ramp out or return silence
		if !_config.enabled {
			if _prevEnabled {
				_reset()
				_internalRender2(frameCount: frameCount, buffers: buffers, filled: &filled)
				Smooth(out: true, frameCount: frameCount, fadeFrameCount: transitionFrames(frameCount), buffers: buffers)
			}
			else {
				FillSilence(frameCount: frameCount, buffers: buffers)
				filled = true
				if let callback = _config.disconnectSource {
					withAudioLock {
						_config.source = nil
						_config.disconnectSource = nil
						config$.source = nil
						config$.disconnectSource = nil
					}
					callback()
				}
			}
		}

		// 3. Enabled: ramp in if needed
		else if !_prevEnabled {
			_prevEnabled = true
			_internalRender2(frameCount: frameCount, buffers: buffers, filled: &filled)
			Smooth(out: false, frameCount: frameCount, fadeFrameCount: transitionFrames(frameCount), buffers: buffers)
		}

		// 4. Simply render
		else {
			_internalRender2(frameCount: frameCount, buffers: buffers, filled: &filled)
		}

		// 5. Notify the monitor (tap) node if connected
		if let monitor = _config.monitor {
			monitor._internalMonitor(frameCount: frameCount, buffers: buffers)
		}
	}


	private func _internalRender2(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		// 1. Pull input data if source is connected, or fill silence
		if let source = _config.source {
			source._internalPull(frameCount: frameCount, buffers: buffers, filled: &filled)
		}
		else if !filled {
			FillSilence(frameCount: frameCount, buffers: buffers)
			filled = true
		}

		// 2. Call the abstract render routine for this node
		if !_config.bypass {
			_render(frameCount: frameCount, buffers: buffers, filled: &filled)
		}
	}


	func _willRender$() {
		_config = config$
	}


	func _reset() {
		_prevEnabled = _config.enabled
		_config.source?._reset()
	}


	// MARK: - Internal: Connection management

	final var _isEnabled: Bool { _config.enabled }


	// MARK: - Private

	private struct Config {
		var monitor: Monitor?
		var source: Source?
		var enabled: Bool
		var bypass: Bool = false
		var disconnectSource: (() -> Void)? // for internal smooth disconnection
	}

	private var config$: Config // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config // config used during the rendering cycle
	private var _prevEnabled: Bool
}
