//
//  EQFilter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 29.01.25.
//

import Foundation
import Accelerate


// The below seems to be the default on iOS/macOS as per https://developer.apple.com/documentation/audiotoolbox/kaudiounitproperty_maximumframesperslice
private let MAX_SCRATCH_BUFFER_CAPACITY = 4096


public enum EQType {
	case peaking
	case lowShelf
	case highShelf
	case lowPass
	case highPass
	case bandPass
}


public let FreqRange: ClosedRange<Float> = 20...20000
public let LogFreqRange: ClosedRange<Float> = log10(FreqRange.lowerBound) ... log10(FreqRange.upperBound)
public let LogFreqWidth = LogFreqRange.width

public let BWRange: ClosedRange<Float> = 0.05...5
public let GainRange: ClosedRange<Float> = -96...24
public let QRange: ClosedRange<Float> = 0.18...28.8


public struct EQParameters: Equatable {

	public init(type: EQType, freq: Float, bw: Float, gain: Float = 0) {
		self.type = type
		self.freq = freq
		self.q = QRange.lowerBound
		self.gain = gain
		self.bw = bw
	}

	public var type: EQType

	public var freq: Float { // Hz, 20 -> 20,000
		didSet { freq = freq.clamped(to: FreqRange) }
	}

	public var logFreq: Float { // 0..1, computed logarithmic frequency (for use with UI sliders)
		get { (log10(freq) - LogFreqRange.lowerBound) / LogFreqWidth }
		set { freq = pow(10, newValue * LogFreqWidth + LogFreqRange.lowerBound) }
	}

	public var q: Float { // 28.8 -> 0.18
		didSet { q = q.clamped(to: QRange) }
	}

	public var gain: Float { // dB, -96 -> 24
		didSet { gain = gain.clamped(to: GainRange) }
	}

	public var bw: Float {	// octaves, 0.05 -> 5.0
		get { 2.88539 * asinh(1 / (2 * q)) }
		set { q = sqrt(pow(2, newValue)) / (pow(2, newValue) - 1) }
	}
}


// MARK: - EQ Filters

/// Internal base class for the single-band EQFilter, and also for internal per-band filters in MultiEQFilter. It doesn't allocate the scratch buffer since we only need one buffer for both single- and multiband EQ nodes.
public class EQBase: Source, @unchecked Sendable {

	fileprivate init(format: StreamFormat, params: EQParameters?, isEnabled: Bool = true) {
		self.sampleRate = format.sampleRate
		self.config$ = params.map {
			EQConfig($0, sampleRate: format.sampleRate)
		}
		_processors = Array(repeating: EQProcessor(), count: format.isStereo ? 2 : 1)
		super.init(isEnabled: isEnabled)
	}

	/// Set EQ parameters or nil to bypass
	public func setParams(_ params: EQParameters?) {
		let newConfig = params.map {
			EQConfig($0, sampleRate: sampleRate)
		}
		withAudioLock {
			config$ = newConfig
		}
	}


	// Internal

	override func _willRender$() {
		super._willRender$()
		_config = config$
	}

	override func _reset() {
		super._reset()
		for i in _processors.indices {
			_processors[i].reset()
		}
	}


	// Private
	private let sampleRate: Double
	private var config$: EQConfig?
	fileprivate var _config: EQConfig?
	fileprivate final var _processors: [EQProcessor] // one per channel, i.e. 1 or 2 processors
}


/// Single-band EQ filter node
public class EQFilter: EQBase, @unchecked Sendable {

	public override init(format: StreamFormat, params: EQParameters? = nil, isEnabled: Bool = true) {
		// This should be allocated as stereo because we use the two-buffer swapping trick when calculating the EQ's per each channel (see _render() below)
		_scratchBuffer = SafeAudioBufferList(isStereo: true, capacity: MAX_SCRATCH_BUFFER_CAPACITY + 2)
		super.init(format: format, params: params, isEnabled: isEnabled)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		guard let configPtr = _config?.unsafePointer() else { return }
		let inData = _scratchBuffer.buffers[0].samples
		let outData = _scratchBuffer.buffers[1].samples
		for i in 0..<buffers.count {
			memcpy(inData + 2, buffers[i].samples, frameCount * SizeOfSample)
			_processors[i].process(config: configPtr, frameCount: frameCount, inData: inData, outData: outData)
			memcpy(buffers[i].samples, outData + 2, frameCount * SizeOfSample)
		}
	}


	private let _scratchBuffer: SafeAudioBufferList // used as a dual in/out scratch buffer for single channel processing; therefore always allocated as stereo
}


/// Multiband EQ filter with fixed number of bands.
public class MultiEQFilter: Source, @unchecked Sendable {

	public init(format: StreamFormat, params: [EQParameters?], isEnabled: Bool = true) {
		// This should be allocated as stereo because we use the two-buffer swapping trick when calculating the EQ's per each channel (see _render() below)
		_scratchBuffer = SafeAudioBufferList(isStereo: true, capacity: MAX_SCRATCH_BUFFER_CAPACITY + 2)
		self.items = params.map {
			EQBase(format: format, params: $0, isEnabled: true)
		}
	}

	/// Set EQ parameters for an individual band, or nil to bypass
	public func setParams(_ i: Int, params: EQParameters?) {
		items[i].setParams(params)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		for i in 0..<buffers.count {
			let audio = buffers[i]
			// In and out buffers will be flipflopping as we progress with bands, this is for efficiency
			let dataA = _scratchBuffer.buffers[0].samples
			let dataB = _scratchBuffer.buffers[1].samples
			var srcIsA: Bool = true
			var copied: Bool = false
			for item in items {
				guard let configPtr = item._config?.unsafePointer() else {
					continue
				}
				if !copied {
					memcpy(dataA + 2, audio.samples, frameCount * SizeOfSample)
					copied = true
				}
				item._processors[i].process(config: configPtr, frameCount: frameCount, inData: srcIsA ? dataA : dataB, outData: srcIsA ? dataB : dataA)
				srcIsA = !srcIsA
			}
			if copied {
				memcpy(audio.samples, (srcIsA ? dataA : dataB) + 2, frameCount * SizeOfSample)
			}
		}
	}

	override func _willRender$() {
		super._willRender$()
		items.forEach {
			$0._willRender$()
		}
	}

	override func _reset() {
		super._reset()
		items.forEach {
			$0._reset()
		}
	}


	private let items: [EQBase]
	private let _scratchBuffer: SafeAudioBufferList // used as a dual in/out scratch buffer for single channel processing; therefore always allocated as stereo
}



// MARK: - Internal structures

private struct EQConfig {
	var b0, b1, b2, a1, a2: Float

	mutating func unsafePointer() -> UnsafeMutablePointer<Float> {
		withUnsafeMutablePointer(to: &b0) { $0 }
	}

	private init() {
		// Currently this constructor is not used
		// TODO: initialize to coeffs that pass through sound
		// Tried .peaking with gain = 0, it leaves strange effects and eventually kills the sound. Is the filter formula correct? Though .lowShelf seems to be working fine as a pass-through filter. Still, will leave this for later.
		// self.init(EQParameters(freq: 20, bw: 5, gain: 0), type: .lowShelf, sampleRate: 44100)
		b0 = 0; b1 = 0; b2 = 0; a1 = 0; a2 = 0
	}

	init(_ params: EQParameters, sampleRate: Double) {
		let omega = 2 * Float.pi * params.freq / Float(sampleRate)
		let cs = cos(omega)
		let alpha = sin(omega) / (2 * params.q)
		var a0: Float

		switch params.type {

			case .lowPass, .highPass:
				let ics = params.type == .lowPass ? 1 - cs : 1 + cs
				a0 = 1 + alpha
				b0 = ics / 2
				b1 = params.type == .lowPass ? ics : -ics
				b2 = ics / 2
				a1 = -2 * cs
				a2 = 1 - alpha

			case .bandPass:
				a0 = 1 + alpha
				b0 = alpha
				b1 = 0
				b2 = -1 * alpha
				a1 = -2 * cs
				a2 = 1 - alpha

			case .peaking:
				let A = sqrt(pow(10, (params.gain / 20)))
				let alpha1 = alpha * A
				let alpha2 = alpha / A
				a0 = 1 + alpha2
				a1 = -2 * cs
				b0 = 1 + alpha1
				b1 = -2 * cs
				b2 = 1 - alpha1
				a2 = 1 - alpha2

			case .lowShelf, .highShelf:
				let A = sqrt(pow(10, (params.gain / 20)))
				let egm = params.type == .lowShelf ? A - 1 : 1 - A
				let egmOmega = egm * cs
				let egp = A + 1
				let egpOmega = egp * cs
				let delta = 2 * sqrt(A) * alpha
				a0 = egp + egm * cs + delta
				b0 = (egp - egmOmega + delta) * A
				b1 = (egm - egpOmega) * 2 * A
				b2 = (egp - egmOmega - delta) * A
				a1 = (egm + egpOmega) * -2
				a2 = egp + egmOmega - delta
		}

		vDSP_vsdiv(unsafePointer(), 1, &a0, unsafePointer(), 1, 5)
	}
}


private struct EQProcessor {
	var k0: Sample = 0
	var k1: Sample = 0
	var k2: Sample = 0
	var k3: Sample = 0

	mutating func process(config: UnsafePointer<Float>, frameCount: Int, inData: UnsafeMutablePointer<Sample>, outData: UnsafeMutablePointer<Sample>) {
		inData[0] = k0
		inData[1] = k1
		outData[0] = k2
		outData[1] = k3
		vDSP_deq22(inData, 1, config, outData, 1, UInt(frameCount))
		k0 = inData[frameCount]
		k1 = inData[frameCount + 1]
		k2 = outData[frameCount]
		k3 = outData[frameCount + 1]
	}

	mutating func reset() {
		k0 = 0
		k1 = 0
		k2 = 0
		k3 = 0
	}
}
