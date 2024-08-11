//
//  Mixer.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation
import Accelerate


final class VolumeControl: Filter {

	let busNumber: Int? // for debug diagnostics only


	init(busNumber: Int? = nil) {
		self.busNumber = busNumber
	}


	override var debugName: String { super.debugName + (busNumber.map { "[\($0)]" } ?? "") }


	func setVolume(_ volume: Float, duration: TimeInterval = 0) {
		withAudioLock {
			let frames = format$.map { Int($0.sampleRate * duration) } ?? 0
			config$ = .init(fadeEnd: volume, fadeFrames: frames)
		}
	}


	// Internal

	override func _filter(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var current = _previous

		if current != _config.fadeEnd {
			// Calculate the level that should be set at the end of this cycle (current)
			if _config.fadeFrames <= frameCount {
				current = _config.fadeEnd
			}
			else {
				let ratio = Float(frameCount) / Float(_config.fadeFrames)
				let delta = (_config.fadeEnd - current) * ratio
				current += delta
				_config.fadeFrames -= frameCount
			}

			// Make a short transition to the new level, then multiply the rest of the buffer by the new factor
			let prevFactor = FactorFromGain(_previous)
			var factor = FactorFromGain(current)
			_previous = current
			let delta = factor - prevFactor
			let transitionFrames = _transitionFrames
			for i in 0..<buffers.count {
				let samples = buffers[i].samples
				for i in 0..<transitionFrames {
					samples[i] *= prevFactor + delta * (Sample(i) / Sample(transitionFrames))
				}
				let rest = samples + transitionFrames
				vDSP_vsmul(rest, 1, &factor, rest, 1, UInt(frameCount - transitionFrames))
			}
		}

		else if current == 0 { // silence
			return FillSilence(frameCount: frameCount, buffers: buffers)
		}

		else if current != 1 { // no ramps, non-1 level
			var factor = FactorFromGain(current)
			for i in 0..<buffers.count {
				let samples = buffers[i].samples
				vDSP_vsmul(samples, 1, &factor, samples, 1, UInt(frameCount))
			}
		}

		return noErr
	}


	override func _willRender$() {
		super._willRender$()
		if let config = config$ {
			_config = config
			config$ = nil
		}
	}


	override func _reset() {
		super._reset()
		_previous = _config.fadeEnd
		_config.fadeFrames = 0
	}


	// Private

	private struct Config {
		var fadeEnd: Float
		var fadeFrames: Int
	}

	private var config$: Config? = nil
	private var _config: Config = .init(fadeEnd: 1, fadeFrames: 0)
	private var _previous: Float = 1
}


final class Mixer: Node {

	typealias Bus = VolumeControl
}
