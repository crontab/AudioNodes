//
//  FFTMeter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 29.01.25.
//

import Foundation
import Accelerate
import AudioUnit


// MARK: - FFT Meter

public let SILENCE_DB: Float = -127

let FFT_LOG_2N = 11
let FFT_FRAMES = 1 << FFT_LOG_2N // 1024, i.e. 48Hz is the frequency of delegate calls
let FFT_NUM_BANDS = FFT_LOG_2N - 1
let SAFE_ZERO_AMPLITUDE: Float = 1.5849e-13 // Don't ask, I don't know. Taken from the Magnetola project.


@MainActor
public protocol FFTMeterDelegate: AnyObject {
	/// Delivers dB levels per frequency band; there are `FFT_NUM_BANDS` values in the `levels` array.
	func fftMeterDidUpdateLevels(_ fftMeter: FFTMeter, levels: [Float])
}


public final class FFTMeter: Monitor, @unchecked Sendable {

	var bandCount: Int { _fft.log2n - 1 }


	public init(format: StreamFormat, isEnabled: Bool = true, delegate: FFTMeterDelegate?) {
		self._circular = .init(isStereo: format.isStereo, capacity: 4096 + FFT_FRAMES)
		self._scratch = .init(isStereo: format.isStereo, capacity: FFT_FRAMES)
		self._levels = Array(repeating: 0, count: FFT_NUM_BANDS)
		self.delegate = delegate
		self._fft = .init(log2n: FFT_LOG_2N)
	}


	// Internal

	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		_ = _circular.enqueue(buffers, toCopy: frameCount)

		while _circular.dequeue(_scratch.buffers, toCopy: _scratch.capacity) {
			// At this point, `scratch` is guaranteed to have `capacity` samples
			for i in 0..<_scratch.buffers.count {
				_fft.compute(fromAudio: _scratch.buffers[i].samples, frameCount: _scratch.capacity)
				// First channel: copy the values
				if i == 0 {
					for j in 0..<_fft.bands.count {
						_levels[j] = _fft.bands[j]
					}
				}
				// Otherwise pick the max
				else {
					for j in 0..<_fft.bands.count {
						_levels[j] = max(_levels[j], _fft.bands[j])
					}
				}
			}
			_didUpdateLevels()
		}
	}


	private func _didUpdateLevels() {
		guard let delegate else { return }
		let levels = _levels // this means that potentially CoW may be triggered on the audio thread; will revise this when Swift fixed arrays become available
		Task.detached { @MainActor in
			delegate.fftMeterDidUpdateLevels(self, levels: levels)
		}
	}


	private let _circular: CircularAudioBuffer
	private let _scratch: SafeAudioBufferList
	private var _levels: [Float] // final result, levels per frequency band
	private weak var delegate: FFTMeterDelegate?
	private let _fft: FFTProcessor
}



// MARK: - FFT Processor

private final class FFTProcessor {

	private(set) var bands: [Float] // log2n - 1 levels in dB


	init(log2n: Int) {
		self.log2n = log2n
		audioLength = 1 << log2n
		fftLength = UInt(audioLength / 2)
		complex = .init(capacity: Int(fftLength))
		levels = Array(repeating: 0, count: Int(fftLength))
		bands = Array(repeating: 0, count: log2n - 1)
		setup = vDSP_create_fftsetup(UInt(log2n), FFTRadix(kFFTRadix2))!
	}


	deinit {
		vDSP_destroy_fftsetup(setup)
		complex.deallocateBuffers()
	}


	func compute(fromAudio audio: UnsafePointer<Float>, frameCount: Int) {
		// 1. Compute FFT
		precondition(frameCount == audioLength)
		vDSP_ctoz(UnsafeRawPointer(audio).assumingMemoryBound(to: DSPComplex.self), 2, &complex, 1, fftLength)
		vDSP_fft_zrip(setup, &complex, 1, UInt(log2n), FFTDirection(kFFTDirection_Forward))
		var factor = 1 / (2 * Float(audioLength))
		vDSP_vsmul(complex.realp, 1, &factor, complex.realp, 1, fftLength)
		vDSP_vsmul(complex.imagp, 1, &factor, complex.imagp, 1, fftLength)

		// 2. Convert to dB
		// 2a. Zero out the Nyquist value
		complex.imagp[0] = 0

		// 2b. Convert the fft data to dB
		vDSP_zvmags(&complex, 1, &levels, 1, fftLength)
		// In order to avoid taking log10 of zero, an adjusting factor is added in to make the minimum value equal -128dB
		var zero = SAFE_ZERO_AMPLITUDE
		vDSP_vsadd(levels, 1, &zero, &levels, 1, fftLength)
		var one: Float = 1
		vDSP_vdbcon(levels, 1, &one, &levels, 1, fftLength, 0);

		// 3. Convert to log2n - 1 bands
		// We take logarithmically growing bands, i.e. 1, 2, 4 ... 128 in case of FFT_LENGTH=256 and take the maximum for each band.
		var j = 0
		for i in bands.indices {
			bands[i] = SILENCE_DB // initial value
			for k in 0...j {
				bands[i] = max(bands[i], levels[j + k + 1])
			}
			j += 1 << i
		}
	}


	fileprivate let log2n: Int
	private let audioLength: Int
	private let fftLength: UInt
	private let setup: FFTSetup
	private var complex: DSPSplitComplex // raw results from the FFT engine, 2 arrays fftLength each
	private var levels: [Float] // levels in dB, fftLength items
}


private extension DSPSplitComplex {

	init(capacity: Int) {
		self.init(realp: .allocate(capacity: capacity), imagp: .allocate(capacity: capacity))
	}

	func deallocateBuffers() {
		realp.deallocate()
		imagp.deallocate()
	}
}
