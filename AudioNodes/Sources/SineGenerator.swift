//
//  SineGenerator.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 10.08.24.
//

import Foundation
import CoreAudio


public final class SineGenerator: Source, StaticDataSource, @unchecked Sendable {

	public let format: StreamFormat
	public var estimatedDuration: TimeInterval { .infinity }


	public init(freq: Float32, volume: Float = 1, format: StreamFormat, isEnabled: Bool = false) {
		self.format = format
		self.freq$ = freq
		self.factor = FactorFromGain(volume)
		self.thetaInc = 2.0 * .pi / format.sampleRate
		precondition(thetaInc > 0)
		super.init(isEnabled: isEnabled)
	}


	public var frequency: Float32 {
		get { withAudioLock { freq$ } }
		set { withAudioLock { freq$ = newValue } }
	}


	override func _willRender$() {
		super._willRender$()
		_freq = freq$
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) {
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
	}


	// Static source protocol
	public func readSync(frameCount: Int, buffers: AudioBufferListPtr, numRead: inout Int) throws(Never) {
		numRead = frameCount
		_willRender$()
		_render(frameCount: frameCount, buffers: buffers)
	}


	public func resetRead() { }


	private let thetaInc: Double
	private let factor: Float

	private var freq$: Float
	private var _freq: Float = 0
	private var _theta: Double = 0
}
