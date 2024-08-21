//
//  Waveform.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 20.08.24.
//

import Foundation
import Accelerate


struct Waveform: Sendable {

	typealias Level = Int8 // -127..0 dB
	static let Range: ClosedRange<Float> = -127...0

	let series: [Level]


	static func fromSource(_ source: StaticDataSource, barsPerSec: Int) -> Self? {
		guard source.resetRead() == noErr else {
			return nil
		}

		let format = source.format
		let samplesPerBar = Int(format.sampleRate) / barsPerSec
		let bufferList = SafeAudioBufferList(isStereo: format.isStereo, capacity: Int(format.sampleRate)) // 1s <- should be in multiples of seconds for simplicity
		let buffers = bufferList.buffers
		let frameCount = buffers[0].sampleCount

		var series: [Level] = []

		while true {
			var numRead = 0 // within 1s
			let status = source.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)
			if status != noErr {
				return nil
			}

			var offset = 0
			while offset < numRead {
				// Compute mean magnitudes (mean of absolute values) per bar for each channel, then take the average and convert to dB
				let sum: Float = buffers.reduce(0) { res, buffer in
					var bar: Sample = 0
					vDSP_meamgv(buffer.samples + offset, 1, &bar, UInt(samplesPerBar))
					return res + bar
				}
				let level = 20 * log10(sum / Float(buffers.count))
				series.append(Waveform.Level(level.clamped(to: Range)))
				offset += samplesPerBar
			}

			if numRead < frameCount {
				break
			}
		}

		return .init(series: series)
	}


	func toHexString() -> String {
		series
			.map { String(format: "%02hhx", $0) }
			.joined()
	}


	static func fromHexString(_ s: String) -> Self {
		.init(series: s.components(maxLength: 2)
			.compactMap { Int($0, radix: 16) }
			.map { Int8(truncatingIfNeeded: $0) })
	}
}


private extension String {
	func components(maxLength: Int) -> [Substring] {
		stride(from: 0, to: count, by: maxLength).map {
			let start = index(startIndex, offsetBy: $0)
			let end = index(start, offsetBy: maxLength, limitedBy: endIndex) ?? endIndex
			return self[start..<end]
		}
	}
}
