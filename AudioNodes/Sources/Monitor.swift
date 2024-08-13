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

	/// Name of the node for debug printing
	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	init(isEnabled: Bool = true) {
		_config = .init(enabled: isEnabled)
		config$ = .init(enabled: isEnabled)
	}


	// Internal

	final func _internalRender(frameCount: Int, buffers: AudioBufferListPtr) {
		withAudioLock {
			_willRender$()
		}
		guard _config.enabled else { return }
		_monitor(frameCount: frameCount, buffers: buffers)
	}


	func _willRender$() {
		_config = config$
	}


	func updateFormat$(_ format: StreamFormat) {
		DLOG("\(debugName).didConnect(\(format.sampleRate), \(format.bufferFrameSize), \(format.isStereo ? "stereo" : "mono"))")
		if format != config$.format {
			config$.format = format
		}
	}


	// Private

	private struct Config {
		var format: StreamFormat?
		var enabled: Bool
	}

	private var config$: Config // user updates this config, to be copied before the next rendering cycle; can only be accessed within audio lock
	private var _config: Config // config used during the rendering cycle
}
