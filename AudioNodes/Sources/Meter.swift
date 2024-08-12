//
//  Meter.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation
import Accelerate


@AudioActor
protocol MeterDelegate: AnyObject, Sendable {
	func meterDidUpdateGains(_ meter: Meter, left: Float, right: Float)
}


private let MIN_LEVEL_DB: Sample = -90
private let BINS_PER_SEC: Float = 22 // 1536 frames for 44.1kHz/512, or 2048 for 48kHz/1024


class Meter: Monitor {

	init(format: StreamFormat, delegate: MeterDelegate) {
		self.delegate = delegate
		_format = format
		_binFrames = max(format.bufferFrameSize, (Int(format.sampleRate / Double(BINS_PER_SEC)) / format.bufferFrameSize) * format.bufferFrameSize)
	}


	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		for i in 0..<min(2, buffers.count) {
			var rms: Sample = 0
			vDSP_rmsqv(buffers[i].samples, 1, &rms, UInt(frameCount))
			let level = (rms == 0) ? MIN_LEVEL_DB : max(MIN_LEVEL_DB, 20 * log10(rms))
			_peakLevels[i] = max(_peakLevels[i], level)
		}

		_peakFrames += frameCount

		if _peakFrames >= _binFrames {
			_didUpdatePeaks(left: _peakLevels[0], right: _peakLevels[1])
			_peakLevels[0] = MIN_LEVEL_DB
			_peakLevels[1] = MIN_LEVEL_DB
			_peakFrames = 0
		}
	}


	override func willConnect$(with format: StreamFormat) {
		super.willConnect$(with: format)
		Assert(format == _format, 51060)
	}


	open func _didUpdatePeaks(left: Sample, right: Sample) {
		guard let delegate else { return }
		Task.detached { @AudioActor in
			delegate.meterDidUpdateGains(self, left: left, right: right)
		}
	}


	// Private

	private weak var delegate: MeterDelegate?
	private let _format: StreamFormat
	private let _binFrames: Int
	private var _peakLevels = [MIN_LEVEL_DB, MIN_LEVEL_DB]
	private var _peakFrames = 0
}
