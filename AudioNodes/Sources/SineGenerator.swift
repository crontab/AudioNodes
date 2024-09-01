//
//  SineGenerator.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


final class SineGenerator: Source, StaticDataSource {

	let format: StreamFormat
	var estimatedDuration: TimeInterval { .infinity }


	init(freq: Float32, volume: Float = 1, format: StreamFormat, isEnabled: Bool = false) {
		self.format = format
		self.freq$ = freq
		self.factor = FactorFromGain(volume)
		self.thetaInc = 2.0 * .pi / format.sampleRate
		precondition(thetaInc > 0)
		super.init(isEnabled: isEnabled)
	}


	var frequency: Float32 {
		get { withAudioLock { freq$ } }
		set { withAudioLock { freq$ = newValue } }
	}


	override func _willRender$() {
		super._willRender$()
		_freq = freq$
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		let samples = buffers[0].samples
		let increment = thetaInc * Double(_freq)
		for frame in 0..<frameCount {
			samples[frame] = Sample(sin(_theta)) * factor
			_theta += increment
			if _theta > 2.0 * .pi {
				_theta -= 2.0 * .pi
			}
		}
		for i in 1..<buffers.count {
			Copy(from: buffers[0], to: buffers[i], frameCount: frameCount)
		}
		return noErr
	}


	// Static source protocol
	func readSync(frameCount: Int, buffers: AudioBufferListPtr, numRead: inout Int) -> OSStatus {
		numRead = frameCount
		_willRender$()
		return _render(frameCount: frameCount, buffers: buffers)
	}


	func resetRead() { }


	private let thetaInc: Double
	private let factor: Float

	private var freq$: Float
	private var _freq: Float = 0
	private var _theta: Double = 0
}
