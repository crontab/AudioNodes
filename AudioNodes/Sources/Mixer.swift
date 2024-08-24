//
//  Mixer.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation
import Accelerate


// MARK: - VolumeControl

/// Audio node/filter that can control the gain. Supports timed transitions. It's a standalone component that's also used internally by the Mixer node.
final class VolumeControl: Source {

	let busNumber: Int? // for debug diagnostics only
	let format: StreamFormat

	var volume: Float { withAudioLock { lastKnownVolume$ } }


	init(format: StreamFormat, initialVolume: Float = 1, busNumber: Int? = nil) {
		self.busNumber = busNumber
		self.format = format
		self.lastKnownVolume$ = initialVolume
		self._config = .init(targetVolume: initialVolume, transitionFrames: 0)
		self._previous = initialVolume
	}


	override var debugName: String { super.debugName + (busNumber.map { "[\($0)]" } ?? "") }


	/// Sets the gain, optionally with timed transition. The normal range for the value is 0...1 but values outside of it are also allowed. Any timed request overrides a previous one, but the transition is always smooth.
	func setVolume(_ volume: Float, duration: TimeInterval = 0) {
		withAudioLock {
			let frames = Int(format.sampleRate * duration)
			config$ = .init(targetVolume: volume, transitionFrames: frames)
		}
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var current = _previous

		if current != _config.targetVolume {
			// Calculate the level that should be set at the end of this cycle (current)
			if _config.transitionFrames <= frameCount {
				current = _config.targetVolume
			}
			else {
				let ratio = Float(frameCount) / Float(_config.transitionFrames)
				let delta = (_config.targetVolume - current) * ratio
				current += delta
				_config.transitionFrames -= frameCount
			}

			// Make a short transition to the new level, then multiply the rest of the buffer by the new factor
			let prevFactor = FactorFromGain(_previous)
			var factor = FactorFromGain(current)
			_previous = current
			let delta = factor - prevFactor
			let transitionFrames = transitionFrames(frameCount)
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

		withAudioLock {
			lastKnownVolume$ = _previous
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
		_previous = _config.targetVolume
		_config.transitionFrames = 0
		lastKnownVolume$ = _previous
	}


	// Private

	private struct Config {
		var targetVolume: Float
		var transitionFrames: Int
	}

	private var config$: Config? = nil
	private var lastKnownVolume$: Float
	private var _config: Config
	private var _previous: Float
}


// MARK: - Mixer

/// Mixer node with a predetermined number of buses; each bus is a VolumeControl object.
class Mixer: Source {

	typealias Bus = VolumeControl

	/// Immutable array of buses; each element is a VolumeControl node.
	final let buses: [Bus] // not atomic because it's immutable


	/// Creates a Mixer object with a given number of buses; up to 128 is allowed.
	init(format: StreamFormat, busCount: Int) {
		Assert(busCount > 0 && busCount <= 128, 51041)
		buses = (0..<busCount).map { Bus(format: format, busNumber: $0) }
		_scratchBuffer = .init(isStereo: format.isStereo, capacity: 4096) // don't want to allocate this under semaphore, should be enough
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var first = true
		for bus in buses {
			let status = first ?
				bus._internalPull(frameCount: frameCount, buffers: buffers)
					: _renderAndMix(node: bus, frameCount: frameCount, buffers: buffers)
			first = false
			if status != noErr {
				return status
			}
		}
		if first { // no connections on buses
			return FillSilence(frameCount: frameCount, buffers: buffers)
		}
		return noErr
	}


	private func _renderAndMix(node: Source, frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var status: OSStatus
		status = node._internalPull(frameCount: frameCount, buffers: _scratchBuffer.buffers)
		for i in 0..<buffers.count {
			let src = _scratchBuffer.buffers[i]
			let dst = buffers[i]
			vDSP_vadd(src.samples, 1, dst.samples, 1, dst.samples, 1, UInt(frameCount))
		}
		return status
	}


	// Private

	private var _scratchBuffer: SafeAudioBufferList
}


// MARK: - EnumMixer

/// Type-safe variant of mixer that takes an `enum` as a basis for accessing the buses. The `enum` should conform to `CaseIterable` and have an `Int` raw value type.
class EnumMixer<Enum: RawRepresentable & CaseIterable>: Mixer where Enum.RawValue == Int {

	init(format: StreamFormat) {
		super.init(format: format, busCount: Enum.allCases.count)
	}

	final subscript (_ index: Enum) -> Bus {
		buses[index.rawValue]
	}
}
