//
//  OfflineProcessor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 22.08.24.
//

import Foundation


/// Processes audio data offline using a given source, sink and a chain of Node objects. The offile processor should be connected as a source at the end of the chain; you then call `run(entry:)` with the first node in the chain as an argument. The `entry` node can even be the processor itself if there are no other nodes in the chain.
public class OfflineProcessor: Source, @unchecked Sendable {

	/// Create an offline processor object with a static source and sink pair. The `divisor` argument is the number of cycles per second; should be in multiples of 25 if you have a Meter or Ducker component in the chain.
	public init(source: StaticDataSource, divisor: Int = 25) {
		self.source = source
		let capacity = Int(ceil(source.format.sampleRate)) / divisor
		self.scratch = SafeAudioBufferList(isStereo: source.format.isStereo, capacity: capacity)
	}


	public func run(entry: Source? = nil, sink: StaticDataSink) -> OSStatus {
		precondition(source.format == sink.format)
		let frameCount = scratch.capacity
		while true {
			numRead = 0 // our _render() below should be called as a result of the chain processing
			var result = (entry ?? self)._internalPull(frameCount: frameCount, buffers: scratch.buffers)
			if result != noErr {
				return result
			}
			var numWritten = 0
			result = sink.writeSync(frameCount: numRead, buffers: scratch.buffers, numWritten: &numWritten)
			if result != noErr {
				return result
			}
			if numRead < frameCount || numWritten < numRead {
				// End of source or end of sink reached
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
	private let scratch: SafeAudioBufferList
	var numRead: Int = 0
}
