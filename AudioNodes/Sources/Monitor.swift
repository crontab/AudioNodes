//
//  Monitor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


// MARK: - Monitor

/// A simpler abstract passive node that can be attached to any audio node using `connectMonitor()`.
class Monitor: @unchecked Sendable {

	/// Indicates whether monitoring should be skipped. If disabled, none of the connected monitors receive data anymore.
	var isEnabled: Bool {
		get { withAudioLock { config$.enabled } }
		set { withAudioLock { config$.enabled = newValue } }
	}

	/// Indicates whether this monitor should skip its own `_monitor()` call. Connected monitors will still receive data.
	var isBypassing: Bool {
		get { withAudioLock { config$.bypass } }
		set { withAudioLock { config$.bypass = newValue } }
	}

	/// Abstract overridable function that's called if it's connected to an audio node. Monitors are not supposed to modify data.
	func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		Abstract()
	}

	/// Connects a monitor object to the given monitor..
	func connectMonitor(_ monitor: Monitor) {
		withAudioLock {
			config$.monitor = monitor
		}
	}

	/// Disconnects the monitor.
	func disconnectMonitor() {
		withAudioLock {
			config$.monitor = nil
		}
	}


	init(isEnabled: Bool = true) {
		_config = .init(enabled: isEnabled)
		config$ = .init(enabled: isEnabled)
	}


	/// Name of the node for debug printing
	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	deinit {
		DLOG("deinit \(debugName)")
	}


	// Internal

	final func _internalMonitor(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		withAudioLock {
			_willRender$()
		}
		if _config.enabled {
			if !_config.bypass {
				_monitor(frameCount: frameCount, buffers: buffers)
			}
			return _config.monitor?._internalMonitor(frameCount: frameCount, buffers: buffers) ?? noErr
		}
		return noErr
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
