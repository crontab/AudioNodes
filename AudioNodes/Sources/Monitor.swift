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

	/// Abstract overridable function that's called if it's connected to an audio node. Monitors are not supposed to modify data.
	func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		Abstract()
	}


	init(isEnabled: Bool = true) {
		_enabled = isEnabled
		enabled$ = isEnabled
	}


	/// Name of the node for debug printing
	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	deinit {
		DLOG("deinit \(debugName)")
	}


	// Internal

	final func _internalRender(frameCount: Int, buffers: AudioBufferListPtr) {
		withAudioLock {
			_willRender$()
		}
		guard _enabled else { return }
		_monitor(frameCount: frameCount, buffers: buffers)
	}


	func _willRender$() {
		_enabled = enabled$
	}


	// Private

	private var enabled$: Bool // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _enabled: Bool // config used during the rendering cycle
}
