//
//  AudioData.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 13.08.24.
//

import Foundation


// MARK: - AudioData

/// Up to 60s of in-memory audio data object that can be read or written to. The object can be used with MemoryPlayer and MemoryRecorder nodes. Thread-safe; can be used in both nodes simultanously.
class AudioData: @unchecked Sendable, Player {

	var capacity: TimeInterval { Double(frameCapacity) / sampleRate }

	var duration: TimeInterval { withWriteLock { Double(framesWritten) / sampleRate } }
	var time: TimeInterval { withReadLock { Double(framesRead) / sampleRate } }
	var isAtEnd: Bool { withWriteLock { withReadLock { framesRead == framesWritten } } }


	init(durationSeconds: Int, sampleRate: Double, isStereo: Bool) {
		Assert(durationSeconds > 0 && durationSeconds <= 60, 51070)
		self.sampleRate = sampleRate
		let chunkCapacity = Int(ceil(sampleRate))
		chunks = (0..<durationSeconds).map { _ in
			SafeAudioBufferList(isStereo: isStereo, capacity: chunkCapacity)
		}
		self.chunkCapacity = chunkCapacity
	}


	@discardableResult
	func write(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		withWriteLock {
			var framesCopied = offset
			while framesCopied < frameCount, framesWritten < frameCapacity {
				let chunk = chunks[framesWritten / chunkCapacity]
				let copied = Copy(from: buffers, to: chunk.buffers, fromOffset: framesCopied, toOffset: framesWritten % chunkCapacity)
				framesCopied += copied
				framesWritten += copied
			}
			return framesCopied - offset
		}
	}


	func prepareRead() { // Player delegate
	}


	@discardableResult
	func read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		let framesWritten = withWriteLock { self.framesWritten }
		return withReadLock {
			var framesCopied = offset
			while framesCopied < frameCount, framesRead < framesWritten {
				let chunk = chunks[framesRead / chunkCapacity]
				let copied = Copy(from: chunk.buffers, to: buffers, fromOffset: framesRead % chunkCapacity, toOffset: framesCopied)
				framesCopied += copied
				framesRead += copied
			}
			return framesCopied - offset
		}
	}


	func resetRead() {
		withReadLock {
			framesRead = 0
		}
	}


	func reset() {
		withWriteLock {
			resetRead()
			framesWritten = 0
		}
	}


	var debugName: String { String(describing: self).components(separatedBy: ".").last! }


	deinit {
		DLOG("deinit \(debugName)")
	}


	// Private

	private let sampleRate: Double
	private let chunkCapacity: Int
	private let chunks: [SafeAudioBufferList]

	private var framesRead: Int = 0
	private var framesWritten: Int = 0

	private var frameCapacity: Int { chunkCapacity * chunks.count }
	private var readSem: DispatchSemaphore = .init(value: 1)
	private var writeSem: DispatchSemaphore = .init(value: 1)

	var delegate: (any PlayerDelegate)? // unused

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


// MARK: - MemoryPlayer

class MemoryPlayer: Node, Player {

	let data: AudioData

	var time: TimeInterval { data.time }
	var duration: TimeInterval { data.duration }
	var isAtEnd: Bool { data.isAtEnd }


	init(data: AudioData, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.data = data
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		read(frameCount: frameCount, buffers: buffers, offset: 0)
		return noErr
	}


	func prepareRead() {
		data.prepareRead()
		withAudioLock {
			_willRender$()
		}
	}


	@discardableResult
	func read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		let result = data.read(frameCount: frameCount, buffers: buffers, offset: offset)
		if result < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: result)
			isEnabled = false
			didEndPlayingAsync()
		}
		else {
			didPlaySomeAsync()
		}
		return result
	}


	// Private

	weak var delegate: PlayerDelegate?
}
