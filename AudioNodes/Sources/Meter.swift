//
//  Meter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation
import Accelerate


/// Audio meter feedback delegate.
@MainActor
public protocol MeterDelegate: AnyObject {
	/// Delivers RMS level measurements. The range is -90 to 0 dB; the update frequency is roughly 25 times per second. Executed on `MainActor`.
	func meterDidUpdateGains(_ meter: Meter, left: Float, right: Float)
}


private let BINS_PER_SEC: Float = 25 // update frequency is 25 times per second, or 40ms


/// An observer node that can measure RMS levels; suitable for UI gauges. The values are returned via the `MeterDelegate` method `meterDidUpdateGains`.
public class Meter: Monitor, @unchecked Sendable {

	/// Creates a meter node; the audio format should be known at the time of creation. You can obtain the format from one of the `System` objects.
	public init(format: StreamFormat, isEnabled: Bool = true, delegate: MeterDelegate?) {
		self.binFrames = Int(format.sampleRate / Double(BINS_PER_SEC))
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}


	// Internal

	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		for i in 0..<min(_peakLevels.count, buffers.count) {
			_peakLevels[i] = max(_peakLevels[i], buffers[i].rmsDb())
		}

		_peakFrames += frameCount

		let binFrames = max(frameCount, (binFrames / frameCount) * frameCount)
		if _peakFrames >= binFrames {
			_didUpdatePeaks(left: _peakLevels[0], right: _peakLevels[1])
			_peakLevels[0] = MIN_LEVEL_DB
			_peakLevels[1] = MIN_LEVEL_DB
			_peakFrames = 0
		}
	}


	func _didUpdatePeaks(left: Sample, right: Sample) {
		guard let delegate else { return }
		Task.detached { @Sendable @MainActor in
			delegate.meterDidUpdateGains(self, left: left, right: right)
		}
	}


	// Private

	private weak var delegate: MeterDelegate?
	private let binFrames: Int
	private var _peakLevels = [MIN_LEVEL_DB, MIN_LEVEL_DB]
	private var _peakFrames = 0
}
