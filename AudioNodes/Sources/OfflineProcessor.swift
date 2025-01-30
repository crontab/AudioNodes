//
//  OfflineProcessor.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 22.08.24.
//

import Foundation


public extension Source {

	/// Processes audio data offline using a given static source, static sink and potentially a chain of Node objects attached to this node. Both source and sink should heva the same format.
	/// The `divisor` argument is the number of cycles per second; should be in multiples of 25 if you have a Meter or Ducker component in the chain. Also beware of the EQ node, it allocates a scratch buffer for 4096 samples.
	/// This is a blocking call and therefore it's recommended to run it on a background thread.
	func runOffline(source: StaticDataSource, sink: StaticDataSink, divisor: Int = 25) throws {
		precondition(source.format == sink.format)
		let frameCount = Int(ceil(source.format.sampleRate)) / divisor
		let scratch = SafeAudioBufferList(isStereo: source.format.isStereo, capacity: frameCount)

		while true {
			// 1. Render source
			var numRead = 0
			var result = source.readSync(frameCount: frameCount, buffers: scratch.buffers, numRead: &numRead)
			if numRead < frameCount {
				FillSilence(frameCount: frameCount, buffers: scratch.buffers, offset: numRead)
			}

			// 2. Now pass the data to the chain of nodes connected to this node
			result = _internalPull(frameCount: frameCount, buffers: scratch.buffers)
			if result != noErr {
				throw AudioError.coreAudio(code: result)
			}

			// 3. Write to the sink
			var numWritten = 0
			result = sink.writeSync(frameCount: numRead, buffers: scratch.buffers, numWritten: &numWritten)
			if result != noErr {
				throw AudioError.coreAudio(code: result)
			}

			// 4. Check the end of data condition on both source and sink
			if numRead < frameCount || numWritten < numRead {
				// End of source or end of sink reached
				return
			}
		}
	}
}
