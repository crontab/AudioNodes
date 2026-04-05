//
//  VoiceFileRecorder.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 05.04.26.
//

import Foundation
import AudioNodes


final class VoiceFileRecorder: FileRecorder, @unchecked Sendable {

	public init(url: URL, format: StreamFormat, compressed: Bool = true, capacity: TimeInterval, isEnabled: Bool = false, delegate: RecorderDelegate? = nil) throws {
		let targetFormat = StreamFormat(sampleRate: 16000, isStereo: false)
		converter = targetFormat != format ? Converter(sourceFormat: format, targetFormat: targetFormat) : nil
		try super.init(url: url, format: targetFormat, fileSampleRate: targetFormat.sampleRate, capacity: capacity, isEnabled: isEnabled, delegate: delegate)
	}

	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		if let converter {
			let (outFrameCount, outBuffers) = converter.convert(frameCount: frameCount, buffers: buffers)
			super._monitor(frameCount: outFrameCount, buffers: outBuffers)
		}
		else {
			super._monitor(frameCount: frameCount, buffers: buffers)
		}
	}

	private let converter: Converter?
}
