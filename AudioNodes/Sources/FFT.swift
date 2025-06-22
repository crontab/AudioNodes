//
//  FFT.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 30/10/2019.
//

import Foundation
import Accelerate
import AudioUnit


public final class FFTProcessor {

	private let log2n: Int
	private let sampleRate: Double
	private let audioLength: Int
	private let setup: FFTSetup

	public private(set) var complex: DSPSplitComplex
	public var bandCount: Int { log2n - 1 }

	@inlinable
	public var realp: UnsafeMutablePointer<Float> { complex.realp }

	@inlinable
	public var imagp: UnsafeMutablePointer<Float> { complex.imagp }


	public init(sampleRate: Double, log2n: Int = 9) {
		self.log2n = log2n
		self.sampleRate = sampleRate
		audioLength = 1 << log2n
		complex = .init(capacity: audioLength / 2)
		setup = vDSP_create_fftsetup(UInt(log2n), FFTRadix(kFFTRadix2))!
	}


	deinit {
		vDSP_destroy_fftsetup(setup)
		complex.deallocateBuffers()
	}


	public func compute(fromAudio audio: UnsafePointer<Float>, frameCount: Int) {
		precondition(frameCount == audioLength)
		let fftLength = audioLength / 2
		vDSP_ctoz(UnsafeRawPointer(audio).assumingMemoryBound(to: DSPComplex.self), 2, &complex, 1, UInt(fftLength))
		vDSP_fft_zrip(setup, &complex, 1, UInt(log2n), FFTDirection(kFFTDirection_Forward))
		var factor = 1 / (2 * Float(audioLength))
		vDSP_vsmul(complex.realp, 1, &factor, complex.realp, 1, UInt(fftLength))
		vDSP_vsmul(complex.imagp, 1, &factor, complex.imagp, 1, UInt(fftLength))
	}
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
