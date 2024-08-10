//
//  SineGenerator.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation


final class SineGenerator: Node {

	init(freq: Float32) {
		freq$ = freq
		super.init()
	}


	var frequency: Float32 {
		get { withAudioLock { freq$ } }
		set { withAudioLock { freq$ = newValue } }
	}


	override func _willRender$() {
		super._willRender$()
		_freq = freq$
	}


	override func willConnect$(with format: StreamFormat?) {
		super.willConnect$(with: format)
		if let format {
			_thetaInc = 2.0 * Double.pi / format.sampleRate
		}
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		precondition(_thetaInc > 0)
		let samples = buffers[0].samples
		let increment = _thetaInc * Double(_freq)
		for frame in 0..<frameCount {
			samples[frame] = Sample(sin(_theta) * Self.amplitude)
			_theta += increment
			if _theta > 2.0 * Double.pi {
				_theta -= 2.0 * Double.pi
			}
		}
		for i in 1..<buffers.count {
			Copy(from: buffers[0], to: buffers[i], frameCount: frameCount)
		}
		return noErr
	}


	private var freq$: Float
	private var _freq: Float = 0
	private var _thetaInc: Double = 0
	private var _theta: Double = 0
	private static let amplitude = 1.0
}
