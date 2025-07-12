//
//  NoiseGate.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 23.08.24.
//

import Foundation
import Accelerate


public let STD_NOISE_GATE: Float = -40
public let STD_NORMAL_PEAK: Float = -12 // for approx. 10-40ms chunks


open class NoiseGate: Source, @unchecked Sendable {

	public init(format: StreamFormat, thresholdDb: Float = STD_NOISE_GATE) {
		self.format = format
		self.thresholdDb = thresholdDb
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		// Max level on all channels
		let level: Sample = buffers
			.map { $0.rmsDb() }
			.max() ?? MIN_LEVEL_DB

		let ramp = frameCount
		if level < thresholdDb {
			let prevOpen = _prevOpen ?? false
			if prevOpen {
				// Closing the gate
				Smooth(out: true, frameCount: frameCount, fadeFrameCount: ramp, buffers: buffers)
			}
			else {
				// Already closed
				FillSilence(frameCount: frameCount, buffers: buffers)
			}
			_prevOpen = false
		}

		else {
			let prevOpen = _prevOpen ?? true
			if !prevOpen {
				// Opening the gate
				Smooth(out: false, frameCount: frameCount, fadeFrameCount: ramp, buffers: buffers)
			}
			else {
				// Do nothing
			}
			_prevOpen = true
		}
	}


	override func _reset() {
		super._reset()
		_prevOpen = nil
	}


	// Private

	private let format: StreamFormat
	private let thresholdDb: Float
	private var _prevOpen: Bool? = nil
}
