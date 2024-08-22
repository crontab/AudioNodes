//
//  AudioData.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 13.08.24.
//

import Foundation


protocol StaticDataSource {
	var format: StreamFormat { get }
	func resetRead() -> OSStatus
	func readSync(frameCount: Int, buffers: AudioBufferListPtr, numRead: inout Int) -> OSStatus // expected to fill silence if numRead < buffer size
}


// MARK: - AudioData

private let MaxDuration = 60

/// Up to 60s of in-memory audio data object that can be read or written to. The object can be used with MemoryPlayer and MemoryRecorder nodes. Thread-safe; can be used in both nodes simultanously.
final class AudioData: @unchecked Sendable, StaticDataSource {

	var capacity: TimeInterval { Double(frameCapacity) / format.sampleRate }
	var duration: TimeInterval { withWriteLock { Double(framesWritten) / format.sampleRate } }
	var time: TimeInterval { withReadLock { Double(framesRead) / format.sampleRate } }
	var isAtEnd: Bool { withWriteLock { withReadLock { framesRead == framesWritten } } }
	var isFull: Bool { withWriteLock { framesWritten == frameCapacity } }
	let format: StreamFormat


	init(durationSeconds: Int, format: StreamFormat) {
		Assert(durationSeconds > 0 && durationSeconds <= MaxDuration, 51070)
		self.format = format
		let chunkCapacity = Int(ceil(format.sampleRate))
		chunks = (0..<durationSeconds).map { _ in
			SafeAudioBufferList(isStereo: format.isStereo, capacity: chunkCapacity)
		}
		self.chunkCapacity = chunkCapacity
	}


	init?(url: URL, format: StreamFormat) {
		guard let file = AudioFileReader(url: url, format: format) else {
			return nil
		}
		let duration = Int(ceil(file.estimatedDuration))
		guard duration <= MaxDuration else {
			return nil
		}
		self.format = format
		self.chunkCapacity = Int(ceil(format.sampleRate))
		var chunks: [SafeAudioBufferList] = []
		for _ in 0..<duration {
			let chunk = SafeAudioBufferList(isStereo: format.isStereo, capacity: chunkCapacity)
			var numRead = 0
			let result = file.readSync(frameCount: chunk.capacity, buffers: chunk.buffers, numRead: &numRead)
			if result != noErr {
				return nil
			}
			chunks.append(chunk)
			framesWritten += numRead
		}
		self.chunks = chunks
	}


	func write(frameCount: Int, buffers: AudioBufferListPtr) -> Int {
		withWriteLock {
			var framesCopied = 0
			while framesCopied < frameCount, framesWritten < frameCapacity {
				let chunk = chunks[framesWritten / chunkCapacity]
				let copied = Copy(from: buffers, to: chunk.buffers, fromOffset: framesCopied, toOffset: framesWritten % chunkCapacity, framesMax: frameCount - framesCopied)
				framesCopied += copied
				framesWritten += copied
			}
			return framesCopied
		}
	}


	func read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		let framesWritten = withWriteLock { self.framesWritten }
		return withReadLock {
			let frameCount = min(frameCount, framesWritten - framesRead)
			var framesCopied = offset
			while framesCopied < frameCount {
				let chunk = chunks[framesRead / chunkCapacity]
				let copied = Copy(from: chunk.buffers, to: buffers, fromOffset: framesRead % chunkCapacity, toOffset: framesCopied, framesMax: frameCount - framesCopied)
				framesCopied += copied
				framesRead += copied
			}
			return framesCopied - offset
		}
	}


	// StaticDataSource protocol
	@discardableResult
	func resetRead() -> OSStatus {
		withReadLock {
			framesRead = 0
		}
		return noErr
	}


	// StaticDataSource protocol
	func readSync(frameCount: Int, buffers: AudioBufferListPtr, numRead: inout Int) -> OSStatus {
		numRead = read(frameCount: frameCount, buffers: buffers, offset: 0)
		if numRead < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: Int(numRead))
		}
		return noErr
	}


	func clear() {
		withWriteLock {
			resetRead()
			framesWritten = 0
		}
	}


	func writeToFile(url: URL, fileSampleRate: Double) -> Bool {
		guard duration > 0 else { return false }
		guard let file = AudioFileWriter(url: url, format: format, fileSampleRate: fileSampleRate, compressed: true, async: false) else {
			return false
		}
		var written = 0
		for chunk in chunks {
			let total = withWriteLock { framesWritten }
			let toWrite = min(chunk.frameCount, total - written)
			if file.writeSync(frameCount: toWrite, buffers: chunk.buffers) != noErr {
				return false
			}
			written += toWrite
			if written == total {
				break
			}
		}
		return true
	}


	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	deinit {
		DLOG("deinit \(debugName)")
	}


	// Private

	private let chunkCapacity: Int
	private let chunks: [SafeAudioBufferList]

	private var framesRead: Int = 0
	private var framesWritten: Int = 0

	private var frameCapacity: Int { chunkCapacity * chunks.count }
	private var readSem: DispatchSemaphore = .init(value: 1)
	private var writeSem: DispatchSemaphore = .init(value: 1)

	private func withReadLock<T>(execute: () -> T) -> T {
		readSem.wait()
		defer { readSem.signal() }
		return execute()
	}

	private func withWriteLock<T>(execute: () -> T) -> T {
		writeSem.wait()
		defer { writeSem.signal() }
		return execute()
	}
}
