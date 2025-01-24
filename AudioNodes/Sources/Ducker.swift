//
//  Ducker.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 16.08.24.
//

import Foundation


class Ducker: Meter, @unchecked Sendable {

	init(format: StreamFormat, isEnabled: Bool = true, delegate: MeterDelegate?, volumeControl: VolumeControl) {
		self.volumeControl = volumeControl
		super.init(format: format, isEnabled: isEnabled, delegate: delegate)
	}


	override func _didUpdatePeaks(left: Sample, right: Sample) {
		super._didUpdatePeaks(left: left, right: right)
		let peak = volumeControl.format.isStereo ? (left + right) / 2 : left
		let normalizedGain = max(peak, MIN_LEVEL_DB) / MIN_LEVEL_DB // -50dB -> 1, 0dB -> 0
		let rising = normalizedGain > volumeControl.volume
		volumeControl.setVolume(normalizedGain, duration: rising ? 1 : 0.2)
	}


	private let volumeControl: VolumeControl
}
