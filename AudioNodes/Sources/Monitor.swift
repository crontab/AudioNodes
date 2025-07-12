//
//  Monitor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


// MARK: - Monitor

/// A simpler abstract passive node that can be attached to any audio node using `connectMonitor()`. Monitors do not modify audio data.
open class Monitor: Node, @unchecked Sendable {

	/// Indicates whether monitoring should be skipped. If disabled, none of the connected monitors receive data anymore.
	public var isEnabled: Bool {
		get { withAudioLock { config$.enabled } }
		set { withAudioLock { config$.enabled = newValue } }
	}

	/// Indicates whether this monitor should skip its own `_monitor()` call. Connected monitors will still receive data.
	public var isBypassing: Bool {
		get { withAudioLock { config$.bypass } }
		set { withAudioLock { config$.bypass = newValue } }
	}

	/// Abstract overridable function that's called if it's connected to an audio node. Monitors are not supposed to modify data.
	func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		Abstract()
	}

	/// Connects another monitor object to the given monitor..
	public func connectMonitor(_ monitor: Monitor) {
		withAudioLock {
			config$.monitor = monitor
		}
	}

	/// Disconnects the monitor.
	public func disconnectMonitor() {
		withAudioLock {
			config$.monitor = nil
		}
	}


	public init(isEnabled: Bool = true) {
		_config = .init(enabled: isEnabled)
		config$ = .init(enabled: isEnabled)
	}


	// Internal

	final func _internalMonitor(frameCount: Int, buffers: AudioBufferListPtr) {
		withAudioLock {
			_willRender$()
		}
		if _config.enabled {
			if !_config.bypass {
				_monitor(frameCount: frameCount, buffers: buffers)
			}
			_config.monitor?._internalMonitor(frameCount: frameCount, buffers: buffers)
		}
	}


	func _willRender$() {
		_config = config$
	}


	// Private

	private struct Config {
		var monitor: Monitor?
		var bypass: Bool = false
		var enabled: Bool
	}

	private var config$: Config
	private var _config: Config
}
