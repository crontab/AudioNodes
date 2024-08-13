//
//  Player.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation


@AudioActor
protocol PlayerDelegate: AnyObject, Sendable {
	func player(_ player: Player, isAt time: TimeInterval)
	func playerDidEndPlaying(_ player: Player)
}


// MARK: - Player


class Player: Node {
	var time: TimeInterval { Abstract() }
	var duration: TimeInterval { Abstract() }
	var isAtEnd: Bool { Abstract() }
}



// MARK: - FilePlayer

class FilePlayer: Player {

	override var time: TimeInterval {
		get { withAudioLock { time$ } }
		set { withAudioLock { setTime$(newValue) } }
	}

	override var duration: TimeInterval { duration$ } // no need for a lock

	override var isAtEnd: Bool { withAudioLock { lastKnownPlayhead$ == file.estimatedTotalFrames } }

	func setAtEnd() { withAudioLock { playhead$ = file.estimatedTotalFrames } }


	init?(url: URL, sampleRate: Double, isStereo: Bool, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		guard let file = AsyncAudioFileReader(url: url, sampleRate: sampleRate, isStereo: isStereo) else {
			return nil
		}
		self.file = file
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
		prepopulateCacheAsync(position: 0)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		_ = _continueRender(frameCount: frameCount, buffers: buffers, offset: 0)
		return noErr
	}


	fileprivate final func _continueRender(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		var framesCopied = offset
		var reachedEnd = false

		while framesCopied < frameCount {
			guard let block = file._blockAt(position: _playhead) else {
				// Assuming this is a cache miss (or i/o error) but not an end of file; can also happen if the playhead was moved significantly, so we'll play silence until the cache is filled again
				prepopulateCacheAsync(position: _playhead)
				break
			}
			let copied = Copy(from: block.buffers, to: buffers, fromOffset: _playhead - block.offset, toOffset: framesCopied, framesMax: frameCount - framesCopied)
			if copied == 0 {
				reachedEnd = true
				break
			}
			_playhead += copied
			framesCopied += copied
		}

		if framesCopied < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: framesCopied)
		}

		if reachedEnd, _isEnabled { // Check enabled status to avoid didEndPlaying() being called twice
			_didEndPlaying(at: _playhead)
		}
		else {
			prepopulateCacheAsync(position: _playhead)
			_didPlaySome(until: _playhead)
		}

		return framesCopied
	}


	private func _didPlaySome(until playhead: Int) {
		withAudioLock {
			// TODO: throttle?
			// let delta = Int(self.file.sampleRate / 25) // 25 fps update rate
			lastKnownPlayhead$ = playhead
		}
		guard let delegate else { return }
		let time = Double(playhead) / file.sampleRate
		Task.detached { @AudioActor in
			delegate.player(self, isAt: time)
		}
	}


	private func _didEndPlaying(at playhead: Int) {
		isEnabled = false
		let total = self.file.estimatedTotalFrames
		withAudioLock {
			lastKnownPlayhead$ = total
		}
		guard let delegate else { return }
		let time = Double(total) / file.sampleRate
		Task.detached { @AudioActor in
			delegate.player(self, isAt: time)
			delegate.playerDidEndPlaying(self)
		}
	}


	override func updateFormat$(_ format: StreamFormat) {
		Assert(format.sampleRate == file.sampleRate && format.isStereo == file.isStereo, 51050)
		super.updateFormat$(format)
	}


	override func _willRender$() {
		super._willRender$()
		if let playhead = playhead$ {
			_playhead = playhead
			playhead$ = nil
			prepopulateCacheAsync(position: playhead)
		}
	}


	// Private

	private func prepopulateCacheAsync(position: Int) {
		let file = file
		Task.detached { @AudioFileActor in
			file.prepopulate(position: position)
		}
	}


	private let file: AsyncAudioFileReader
	private weak var delegate: PlayerDelegate?

	private var lastKnownPlayhead$: Int = 0
	private var playhead$: Int?
	private var _playhead: Int = 0

	// Internal methods exposed mainly for QueuePlayer to avoid recursive semaphore locks:
	fileprivate var time$: TimeInterval { Double(lastKnownPlayhead$) / file.sampleRate }
	fileprivate func setTime$(_ t: TimeInterval) { playhead$ = Int(t * file.sampleRate).clamped(to: 0...file.estimatedTotalFrames) }
	fileprivate var duration$: TimeInterval { Double(file.estimatedTotalFrames) / file.sampleRate }
}


// MARK: - QueuePlayer

/// Meta-player that provides gapless playback of multiple files
class QueuePlayer: Player {

	override var time: TimeInterval {
		get { withAudioLock { time$ } }
		set { withAudioLock { setTime$(newValue) } }
	}

	override var duration: TimeInterval { withAudioLock { items$.map { $0.duration$ }.reduce(0, +) } }

	override var isAtEnd: Bool { withAudioLock { !items$.indices.contains(lastKnownIndex$) } }


	/// Adds a file player to the queue.
	func addFile(url: URL) -> Bool {
		guard let player = FilePlayer(url: url, sampleRate: sampleRate, isStereo: isStereo, isEnabled: true) else {
			return false
		}
		withAudioLock {
			items$.append(player)
		}
		return true
	}


	init(sampleRate: Double, isStereo: Bool, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.sampleRate = sampleRate
		self.isStereo = isStereo
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var framesWritten = 0

		while true {
			if !_items.indices.contains(_currentIndex) {
				FillSilence(frameCount: frameCount, buffers: buffers, offset: framesWritten)
				break
			}
			let player = _items[_currentIndex]
			// Note that we bypass the usual rendering call _internalRender(). This is a bit dangerous in case changes are made in Node or FilePlayer. But in any case the player objects are fully managed by QueuePlayer so we go straight to what we need:
			player._willRender$()
			framesWritten += player._continueRender(frameCount: frameCount, buffers: buffers, offset: framesWritten)
			if framesWritten >= frameCount {
				break
			}
			_currentIndex += 1
		}

		if framesWritten < frameCount, _isEnabled {
			_didEndPlaying()
		}
		else {
			_didPlaySome()
		}

		withAudioLock {
			lastKnownIndex$ = _currentIndex
		}
		return noErr
	}


	private func _didPlaySome() {
		guard let delegate else { return }
		let time = time
		Task.detached { @AudioActor in
			delegate.player(self, isAt: time)
		}
	}


	private func _didEndPlaying() {
		isEnabled = false
		guard let delegate else { return }
		let time = duration
		Task.detached { @AudioActor in
			delegate.player(self, isAt: time)
			delegate.playerDidEndPlaying(self)
		}
	}


	override func _willRender$() {
		super._willRender$()
		_items = items$
		if let currentIndex = currentIndex$ {
			_currentIndex = currentIndex
			currentIndex$ = nil
		}
	}


	// Private

	private var time$: TimeInterval {
		items$[..<lastKnownIndex$].map { $0.duration$ }.reduce(0, +)
			+ (items$.indices.contains(lastKnownIndex$) ? items$[lastKnownIndex$].time$ : 0)
	}


	private func setTime$(_ newValue: TimeInterval) {
		var time = newValue
		for i in items$.indices {
			let item = items$[i]
			if time == 0 {
				// succeeding item, reset to 0
				item.setTime$(0)
			}
			else if time >= item.duration$ {
				// preceding item, do nothing
				time -= item.duration$
			}
			else {
				// an item that should become current
				currentIndex$ = i
				item.setTime$(time)
				time = 0
			}
		}
	}


	private let sampleRate: Double
	private let isStereo: Bool
	private weak var delegate: PlayerDelegate?

	private var items$: [FilePlayer] = []
	private var _items: [FilePlayer] = []
	private var lastKnownIndex$: Int = 0
	private var currentIndex$: Int?
	private var _currentIndex: Int = 0
}
