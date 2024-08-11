//
//  AudioFileReader.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation
import AudioToolbox


@globalActor
actor AudioFileActor {
	static var shared = AudioFileActor()
}


@AudioFileActor
class AudioFileReader {

	let url: URL
	let sampleRate: Double
	let isStereo: Bool
	nonisolated let fileRef: ExtAudioFileRef
	let lengthFactor: Double
	let estimatedTotalFrames: Int


	nonisolated
	init?(url: URL, sampleRate: Double, isStereo: Bool) {
		self.url = url
		self.sampleRate = sampleRate
		self.isStereo = isStereo

		var tempFileRef: ExtAudioFileRef?
		var status = ExtAudioFileOpenURL(url as CFURL, &tempFileRef)
		guard status == noErr, tempFileRef != nil else {
			return nil
		}

		fileRef = tempFileRef!

		var fileDescr = AudioStreamBasicDescription()
		var size: UInt32 = SizeOf(fileDescr)
		status = ExtAudioFileGetProperty(fileRef, kExtAudioFileProperty_FileDataFormat, &size, &fileDescr)
		if status != noErr {
			ExtAudioFileDispose(fileRef)
			DLOG("AsyncAudioFile: file open error")
			return nil
		}

		var descr = AudioStreamBasicDescription.canonical(isStereo: isStereo, sampleRate: sampleRate)
		status = ExtAudioFileSetProperty(fileRef, kExtAudioFileProperty_ClientDataFormat, SizeOf(descr), &descr)
		if status != noErr {
			ExtAudioFileDispose(fileRef)
			DLOG("AsyncAudioFile: failed to get audio descriptor")
			return nil
		}

		if descr.mChannelsPerFrame > fileDescr.mChannelsPerFrame {
			precondition(descr.mChannelsPerFrame == 2 && fileDescr.mChannelsPerFrame == 1)
			var converter: AudioConverterRef?
			var size: UInt32 = SizeOf(converter)
			NotError(ExtAudioFileGetProperty(fileRef, kExtAudioFileProperty_AudioConverter, &size, &converter), 51018)
			var channelMap = Array<Int32>(repeating: 0, count: Int(descr.mChannelsPerFrame))
			NotError(AudioConverterSetProperty(converter!, kAudioConverterChannelMap, UInt32(MemoryLayout<Int32>.size * channelMap.count), &channelMap), 51019)
		}

		var fileFrames: Int64 = 0
		size = SizeOf(fileFrames)
		status = ExtAudioFileGetProperty(fileRef, kExtAudioFileProperty_FileLengthFrames, &size, &fileFrames)
		if status != noErr {
			ExtAudioFileDispose(fileRef)
			DLOG("AsyncAudioFile: failed to set audio descriptor")
			return nil
		}

		// If the file reader does resampling, we need to store the resampling factor so that we can correctly seek() within the file
		lengthFactor = fileDescr.mSampleRate / sampleRate
		estimatedTotalFrames = Int(ceil(Double(fileFrames) / lengthFactor))
#if DEBUG && AUDIO_FILE_LOGGING
		DLOG("AudioFile.estimatedTotalFrames: \(estimatedTotalFrames)")
#endif
	}


	deinit {
		ExtAudioFileDispose(fileRef)
	}


	func readSync(frameCount: Int, buffers: AudioBufferListPtr, numRead: inout UInt32) -> OSStatus {
		for i in 0..<buffers.count {
			buffers[i].sampleCount = frameCount
		}
		numRead = UInt32(frameCount)
		let status = ExtAudioFileRead(fileRef, &numRead, buffers.unsafeMutablePointer)
		if status != noErr {
			numRead = 0
			FillSilence(frameCount: frameCount, buffers: buffers)
			return status
		}
		if numRead < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: Int(numRead))
		}
		return noErr
	}
}


// MARK: - AsyncAudioFileReader

// Internal async audio file reader with caching

final class AsyncAudioFileReader: AudioFileReader {

	// Caches a small number of blocks; uses linear search for simplicity
	private struct Cache {
		private let capacity: Int
		private var list: [Block] = []
		private let semaphore = DispatchSemaphore(value: 1)

		init(capacity: Int) {
			precondition(capacity > 0 && capacity < 16)
			self.capacity = capacity
		}

		func blockFor(offset: Int) -> Block? {
			semaphore.wait()
			defer { semaphore.signal() }
			// The element we are looking for will likely be the first or second
			return list.first { $0.offset == offset }
		}

		mutating func setBlockFor(offset: Int, _ newValue: Block) {
			semaphore.wait()
			defer { semaphore.signal() }
			if let oldIndex = list.firstIndex(where: { $0.offset == offset } ) {
				list.remove(at: oldIndex)
			}
			if list.count == capacity {
				list.removeLast()
			}
			list.insert(newValue, at: 0)
		}

		mutating func evictTail() -> Block? {
			semaphore.wait()
			defer { semaphore.signal() }
			return list.count >= capacity ? list.removeLast() : nil
		}
	}


	final class Block: SafeAudioBufferList {
		private(set) var offset: Int
		private(set) var count: Int

		var isEmpty: Bool { count == 0 }

		init(isStereo: Bool, offset: Int, capacity: Int) {
			self.offset = offset
			self.count = 0
			super.init(isStereo: isStereo, capacity: capacity)
#if AUDIO_FILE_LOGGING
			DLOG("AsyncAudioFile: new block \(offset)")
#endif
		}

		func read(from fileRef: ExtAudioFileRef!, offset: Int, lengthFactor: Double) -> Bool {
			self.offset = offset

			for i in 0..<buffers.count {
				buffers[i].sampleCount = capacity
			}

			var status = ExtAudioFileSeek(fileRef, Int64(Double(offset) * lengthFactor))
			if status != noErr {
				return false
			}

			var numRead: UInt32 = UInt32(capacity)
			status = ExtAudioFileRead(fileRef, &numRead, buffers.unsafeMutablePointer)
			if status != noErr {
				return false
			}
			count = Int(numRead)

#if AUDIO_FILE_LOGGING
			DLOG("AsyncAudioFile: block \(offset) read, length \(numRead)")
#endif
			return true
		}

		deinit {
#if AUDIO_FILE_LOGGING
			DLOG("AsyncAudioFile: block \(offset) discarded")
#endif
		}
	}


	private let blockSize: Int
	private(set) var exactTotalFrames: Int?

	nonisolated(unsafe) // protected by a semaphore
	private var cachedBlocks = Cache(capacity: 8)


	override init?(url: URL, sampleRate: Double, isStereo: Bool) {
		blockSize = Int(sampleRate) // * 2
		super.init(url: url, sampleRate: sampleRate, isStereo: isStereo)
	}


	func ensureCached(position: Int) {
		precondition(position >= 0)
		for i in 0...2 { // load up to 3 blocks
			let blockOffset = ((position / blockSize) + i) * blockSize
			if let exactTotalFrames, blockOffset >= exactTotalFrames {
				break
			}
			if cachedBlocks.blockFor(offset: blockOffset) == nil {
				// Try to reuse a block evicted from the cache tail, otherwise allocate a new one
				// TODO: potentially this is wrong as the block being evicted may be in use by the audio rendering thread, though very unlikely to happen
				let block = cachedBlocks.evictTail() ?? Block(isStereo: isStereo, offset: blockOffset, capacity: blockSize)
				if block.read(from: fileRef, offset: blockOffset, lengthFactor: lengthFactor) {
					if block.count < blockSize {
						exactTotalFrames = block.offset + block.count
					}
					cachedBlocks.setBlockFor(offset: blockOffset, block)
					if block.isEmpty {
						// Empty block is possible if the total number of samples is a multiple of the block size; we should keep it so that that caller triggers an end of file
						// TODO: allocate a special empty block wih t0 memory overhead?
#if AUDIO_FILE_LOGGING
						DLOG("AsyncAudioFile: empty block")
#endif
					}
				}
			}
		}
	}


	// Can be called from the audio thread
	nonisolated
	func _blockAt(position: Int) -> Block? {
		let offset = (position / blockSize) * blockSize
		return cachedBlocks.blockFor(offset: offset)
	}
}
