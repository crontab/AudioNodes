//
//  Waveform.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 20.08.24.
//

import Foundation
import Accelerate


public struct Waveform: Sendable {

	public typealias Level = Int8 // -127..0 dB
	static let Range: ClosedRange<Float> = -127...0

	public let ticks: [Level]
	public let lower: Level? // can be nil if ticks are empty or if it's all silence
	public let upper: Level?


	public init(ticks: [Level]) {
		self.ticks = ticks
		var lower, upper: Level?
		for tick in ticks {
			guard tick > Level(MIN_LEVEL_DB) else { continue }
			lower = lower.map { min($0, tick) } ?? tick
			upper = upper.map { max($0, tick) } ?? tick
		}
		self.lower = lower
		self.upper = upper
	}


	public var range: ClosedRange<Float>? {
		guard let lower, let upper, lower <= upper else {
			return nil
		}
		return Float(lower)...Float(upper)
	}


	public func downsampled(by divisor: Int) -> Waveform {
		.init(ticks: ticks
			.components(maxLength: divisor)
			.map { Level($0.map(Int.init).reduce(0, +) / $0.count) })
	}


	public static func fromSource(_ source: StaticDataSource, ticksPerSec: Int) throws -> Self {
		let format = source.format
		let samplesPerTick = Int(format.sampleRate) / ticksPerSec
		let bufferList = SafeAudioBufferList(isStereo: format.isStereo, capacity: Int(format.sampleRate)) // 1s <- should be in multiples of seconds for simplicity
		let buffers = bufferList.buffers
		let frameCount = buffers[0].sampleCount

		var ticks: [Level] = []

		while true {
			var numRead = 0 // within 1s
			try source.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)

			var offset = 0
			while offset < numRead {
				let level = buffers
					.map { $0.rmsDb(frameCount: min(samplesPerTick, numRead - offset), offset: offset) }
					.reduce(0, +) / Float(buffers.count)
				ticks.append(Level(level.clamped(to: Self.Range)))
				offset += samplesPerTick
			}

			if numRead < frameCount {
				break
			}
		}

		return .init(ticks: ticks)
	}


	public func toHexString() -> String {
		ticks
			.map { String(format: "%02hhx", $0) }
			.joined()
	}


	public static func fromHexString(_ s: String) -> Self {
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
