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

	let ticks: [Level]


	func downsampled(by divisor: Int) -> Waveform {
		.init(ticks: ticks
			.components(maxLength: divisor)
			.map { Level($0.map(Int.init).reduce(0, +) / $0.count) })
	}


	static func fromSource(_ source: StaticDataSource, ticksPerSec: Int) -> Self? {
		let format = source.format
		let samplesPerTick = Int(format.sampleRate) / ticksPerSec
		let bufferList = SafeAudioBufferList(isStereo: format.isStereo, capacity: Int(format.sampleRate)) // 1s <- should be in multiples of seconds for simplicity
		let buffers = bufferList.buffers
		let frameCount = buffers[0].sampleCount

		var ticks: [Level] = []

		while true {
			var numRead = 0 // within 1s
			let status = source.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)
			if status != noErr {
				return nil
			}

			var offset = 0
			while offset < numRead {
				let level = buffers
					.map { $0.rmsDb(frameCount: samplesPerTick, offset: offset) }
					.reduce(0, +) / Float(buffers.count)
				ticks.append(Level(level.clamped(to: Range)))
				offset += samplesPerTick
			}

			if numRead < frameCount {
				break
			}
		}

		return .init(ticks: ticks)
	}


	func toHexString() -> String {
		ticks
			.map { String(format: "%02hhx", $0) }
			.joined()
	}


	static func fromHexString(_ s: String) -> Self {
		.init(ticks: s.components(maxLength: 2)
			.compactMap { Int($0, radix: 16) }
			.map { Int8(truncatingIfNeeded: $0) })
	}
}


private extension Collection {

	func components(maxLength: Int) -> [SubSequence] {
		stride(from: 0, to: count, by: maxLength).map {
			let start = index(startIndex, offsetBy: $0)
			let end = index(start, offsetBy: maxLength, limitedBy: endIndex) ?? endIndex
			return self[start..<end]
		}
	}
}
