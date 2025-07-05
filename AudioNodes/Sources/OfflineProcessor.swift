//
//  OfflineProcessor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 22.08.24.
//

import Foundation
import CoreAudio


public extension StaticDataSource {

	typealias OfflineCallback = (_ time: TimeInterval, _ frameCount: Int, _ buffers: AudioBufferListPtr) throws -> Int

	/// Processes audio data offline using a given static source, static sink and potentially a chain of Node objects attached to this node. Both source and sink should have the same format.
	/// The `ticksPerSec` argument is the number of cycles per second; should be in multiples of 25 if you have a Meter or Ducker component in the chain. Also beware of the EQ node, it allocates a scratch buffer for 4096 samples.
	/// This is a blocking call and therefore it's recommended to run it on a background thread.
	func runOffline(sink: StaticDataSink, node: Source?, ticksPerSec: Int = 25) throws {
		precondition(format == sink.format)
		try runOffline(node: node, ticksPerSec: ticksPerSec) { _, frameCount, buffers in
			try sink.writeSync(frameCount: frameCount, buffers: buffers)
		}
	}


	/// Processes audio data offline using a given static source and potentially a chain of Node objects attached to this node. The callback receives a timestamp and the resulting buffer data with each tick.
	/// The `ticksPerSec` argument is the number of cycles per second; should be in multiples of 25 if you have a Meter or Ducker component in the chain. Also beware of the EQ node, it allocates a scratch buffer for 4096 samples.
	/// This is a blocking call and therefore it's recommended to run it on a background thread.
	func runOffline(node: Source? = nil, ticksPerSec: Int = 25, callback: OfflineCallback) throws {
		let frameCount = Int(ceil(format.sampleRate)) / ticksPerSec
		let scratch = SafeAudioBufferList(isStereo: format.isStereo, capacity: frameCount)

		var totalRead = 0
		while true {
			// 1. Render source
			var numRead = 0
			try readSync(frameCount: frameCount, buffers: scratch.buffers, numRead: &numRead)
			if numRead < frameCount {
				FillSilence(frameCount: frameCount, buffers: scratch.buffers, offset: numRead)
			}

			// 2. Now pass the data to the chain of nodes connected to this node
			node?._internalPull(frameCount: frameCount, buffers: scratch.buffers)

			// 3. Write to the sink
			let numWritten = try callback(Double(totalRead) / format.sampleRate, numRead, scratch.buffers)

			// 4. Check the end of data condition on both source and sink
			if numRead < frameCount || numWritten < numRead {
				// End of source or end of sink reached
				break
			}

			totalRead += numRead
		}
	}
}
