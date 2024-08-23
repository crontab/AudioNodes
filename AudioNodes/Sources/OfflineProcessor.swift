//
//  OfflineProcessor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 22.08.24.
//

import Foundation


/// Processes audio data offline using a given source, sink and a chain of Node objects. The offile driver should be connected as a source at the end of the chain; you then call `process(entry:)` with the first node in the chain as an argument.
class OfflineProcessor: Node {

	init(source: StaticDataSource, sink: StaticDataSink, divisor: Int = 100) {
		precondition(source.format == sink.format)
		self.source = source
		self.sink = sink
		let capacity = Int(ceil(source.format.sampleRate)) / divisor
		self.scratch = SafeAudioBufferList(isStereo: source.format.isStereo, capacity: capacity)
	}


	func process(entry: Node) -> OSStatus {
		let frameCount = scratch.capacity
		while true {
			numRead = 0 // our _render() below should be called as a result of the chain processing
			var result = entry._internalPull(frameCount: numRead, buffers: scratch.buffers)
			if result != noErr {
				return result
			}
			var numWritten = 0
			result = sink.writeSync(frameCount: numRead, buffers: scratch.buffers, numWritten: &numWritten)
			if result != noErr {
				return result
			}
			if numRead < frameCount {
				return noErr
			}
		}
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		let result = source.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)
		if numRead < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: numRead)
		}
		return result
	}


	// Private

	private let source: StaticDataSource
	private let sink: StaticDataSink
	private let scratch: SafeAudioBufferList
	var numRead: Int = 0
}
