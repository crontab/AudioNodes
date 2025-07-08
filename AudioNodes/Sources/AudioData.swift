//
//  AudioData.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 13.08.24.
//

import Foundation
import CoreAudio


public protocol StaticDataSource {
	var format: StreamFormat { get }
	var estimatedDuration: TimeInterval { get }
	func resetRead()
	func readSync(frameCount: Int, buffers: AudioBufferListPtr) throws -> Int // returns samples read
}


public protocol StaticDataSink {
	var format: StreamFormat { get }
	func writeSync(frameCount: Int, buffers: AudioBufferListPtr) throws -> Int // returns samples written
}


// MARK: - AudioData

private let MaxDuration = 60

/// Up to 60s of in-memory audio data object that can be read or written to. The object can be used with MemoryPlayer and MemoryRecorder nodes. Thread-safe; can be used in both nodes simultanously.
public final class AudioData: @unchecked Sendable, StaticDataSource, StaticDataSink {

	public var capacity: Int { chunks.count }
	public var duration: TimeInterval {
		get { withWriteLock { Double(framesWritten) / format.sampleRate } }
		set { withWriteLock { framesWritten = Int(newValue * format.sampleRate).clamped(to: 0...frameCapacity) } }
	}
	public var time: TimeInterval {
		get { withReadLock { Double(framesRead) / format.sampleRate } }
		set { withWriteLock { withReadLock { framesRead = Int(newValue * format.sampleRate).clamped(to: 0...framesWritten) } } }
	}
	public var isAtEnd: Bool { withWriteLock { withReadLock { framesRead == framesWritten } } }
	public var isFull: Bool { withWriteLock { framesWritten == frameCapacity } }
	public let format: StreamFormat
	public var estimatedDuration: TimeInterval { duration }


	public init(durationSeconds: Int, format: StreamFormat) {
		Assert(durationSeconds > 0 && durationSeconds <= MaxDuration, 51070)
		self.format = format
		let chunkCapacity = Int(ceil(format.sampleRate)) // 1s
		chunks = (0..<durationSeconds).map { _ in
			SafeAudioBufferList(isStereo: format.isStereo, capacity: chunkCapacity)
		}
		self.chunkCapacity = chunkCapacity
	}


	public init(url: URL, format: StreamFormat) throws {
		let file = try AudioFileReader(url: url, format: format)
		let duration = min(Int(ceil(file.estimatedDuration)), MaxDuration)
		self.format = format
		self.chunkCapacity = Int(ceil(format.sampleRate)) // 1s
		var chunks: [SafeAudioBufferList] = []
		for _ in 0..<duration {
			let chunk = SafeAudioBufferList(isStereo: format.isStereo, capacity: chunkCapacity)
			let numRead = try file.readSync(frameCount: chunk.capacity, buffers: chunk.buffers)
			chunks.append(chunk)
			framesWritten += numRead
		}
		self.chunks = chunks
	}


	/// Creates an AudioData object that shares the buffers with a given object but has its own read pointer. Recommended only for reading.
	public init(duplicate from: AudioData) {
		format = from.format
		chunkCapacity = from.chunkCapacity
		chunks = from.chunks
		framesWritten = from.framesWritten
	}


	public func write(frameCount: Int, buffers: AudioBufferListPtr) -> Int {
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


	public func read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
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


	public func resetRead() {
		withReadLock {
			framesRead = 0
		}
	}


	// StaticDataSource protocol
	public func readSync(frameCount: Int, buffers: AudioBufferListPtr) throws(Never) -> Int {
		return read(frameCount: frameCount, buffers: buffers, offset: 0)
	}


	// StaticDataSink protocol
	public func writeSync(frameCount: Int, buffers: AudioBufferListPtr) throws(Never) -> Int {
		write(frameCount: frameCount, buffers: buffers)
	}


	public func clear() {
		withWriteLock {
			resetRead()
			framesWritten = 0
		}
	}


	public func writeToFile(url: URL, fileSampleRate: Double) throws {
		guard duration > 0 else { return }
		let file = try AudioFileWriter(url: url, format: format, fileSampleRate: fileSampleRate, compressed: true, async: false)
		var written = 0
		for chunk in chunks {
			let total = withWriteLock { framesWritten }
			let toWrite = min(chunk.frameCount, total - written)
			let numWritten = try file.writeSync(frameCount: toWrite, buffers: chunk.buffers)
			written += numWritten
			if written == total {
				break
			}
		}
	}


	var debugName: String { String(describing: type(of: self)) }


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
