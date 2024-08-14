//
//  Player.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation


/// Player feedback delegate; used with both `FilePlayer` and `QueuePlayer`.
@AudioActor
protocol PlayerDelegate: AnyObject, Sendable {

	/// Called by a player node approximately every 10ms. In GUI apps, make sure you reduce the frequency of UI updates since updating them at 100fps may lead to interruptions in audio playback and other undesirable effects. The method is executed on `AudioActor`. This method is also called at the end of a playback just before a call to `playerDidEndPlaying()`.
	func player(_ player: Player, isAt time: TimeInterval)

	/// Called when a given player finishes the playback. Executed on `AudioActor`.
	func playerDidEndPlaying(_ player: Player)
}


// MARK: - Abstract Player

/// Abstract node that defines the most basic player interface. Passed as an argument in `PlayerDelegate` methods; also FilePlayer, QueuePlayer and AudioData conform to this protocol.
class Player: Node {
	var time: TimeInterval { 0 }
	var duration: TimeInterval { 0 }
	var isAtEnd: Bool { true }

	init(isEnabled: Bool, delegate: PlayerDelegate?) {
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}

	final func didPlaySomeAsync() {
		guard let delegate else { return }
		Task.detached { @AudioActor in
			delegate.player(self, isAt: self.time)
		}
	}

	final func didEndPlayingAsync() {
		guard let delegate else { return }
		Task.detached { @AudioActor in
			delegate.player(self, isAt: self.duration)
			delegate.playerDidEndPlaying(self)
		}
	}

	private weak var delegate: PlayerDelegate?
}



// MARK: - FilePlayer

/// Loads and plays an audio file; backed by the ExtAudioFile\* system interface. For each file that you want to play you create a separate FilePlayer node. This component uses a fixed amount of memory regarless of the file size; it employs smart look-ahead buffering.
/// You normally use the `isEnable` property to start and stop the playback. When disabled, this node returns silence to the upstream nodes.
/// Once end of file is reached, `isEnable` flips to `false` automatically. You can restart the playback by setting `time` to `0` and enabling the node again.
/// You can pass a delegate to the constructor of `FilePlayer`; your delegate should conform to Sendable and the overridden methods should assume being executed on `AudioActor`.
class FilePlayer: Player {

	/// Get or set the current time within the file. The granularity is approximately 10ms.
	override var time: TimeInterval {
		get { withAudioLock { time$ } }
		set { withAudioLock { time$ = newValue } }
	}

	/// Returns the total duration of the audio file. If the system sampling rate is the same as the file's own then the value is highly accurate; however if it's not then this value may be slightly off due to floating point arithmetic quirks. Most of the time the inaccuracy may be ignored in your code.
	override var duration: TimeInterval { duration$ } // no need for a lock

	/// Indicates whether end of file was reached while playing the file.
	override var isAtEnd: Bool { withAudioLock { lastKnownPlayhead$ == file.estimatedTotalFrames } }

	func setAtEnd() { withAudioLock { playhead$ = file.estimatedTotalFrames } }

	/// Creates a file player node for a given local audio file; note that remote URL's aren't supported. If any kind of error occurs while attempting to open the file, the constructor returns nil.
	/// The `format` argument should be the same as the current system output's format which you can obtain via `System`'s `.streamFormat` property.
	init?(url: URL, format: StreamFormat, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		guard let file = AsyncAudioFileReader(url: url, format: format) else {
			return nil
		}
		self.file = file
		super.init(isEnabled: isEnabled, delegate: delegate)
		prepopulateCacheAsync(position: 0)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		read(frameCount: frameCount, buffers: buffers, offset: 0)
		return noErr
	}


	// This method is also called directly from QueuePlayer, i.e. bypassing the usual rendering chain; it's because QueuePlayer needs an extra argument `offset`.
	@discardableResult
	fileprivate final func read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
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

		if reachedEnd {
			isEnabled = false
			withAudioLock {
				lastKnownPlayhead$ = file.estimatedTotalFrames
			}
			didEndPlayingAsync()
		}
		else {
			prepopulateCacheAsync(position: _playhead)
			withAudioLock {
				lastKnownPlayhead$ = _playhead
			}
			didPlaySomeAsync()
		}

		return framesCopied - offset
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

	private var lastKnownPlayhead$: Int = 0
	private var playhead$: Int?
	private var _playhead: Int = 0

	// Internal methods exposed mainly for QueuePlayer to avoid recursive semaphore locks:
	fileprivate var time$: TimeInterval {
		get { Double(lastKnownPlayhead$) / file.format.sampleRate }
		set { playhead$ = Int(newValue * file.format.sampleRate).clamped(to: 0...file.estimatedTotalFrames) }
	}

	fileprivate var duration$: TimeInterval { Double(file.estimatedTotalFrames) / file.format.sampleRate }
}


// MARK: - QueuePlayer

/// Meta-player that provides gapless playback of multiple files. This node treats a series of files as a whole, it supports time positioning and `duration` within the whole. Think of Pink Floyd's *Wish You Were Here*, you absolutely *should* provide gapless playback for the entire album. Questions?
class QueuePlayer: Player {

	/// Gets and sets the time position within the entire series of audio files.
	override var time: TimeInterval {
		get { withAudioLock { time$ } }
		set { withAudioLock { time$ = newValue } }
	}

	/// Returns the total duration of the entire series of audio files.
	override var duration: TimeInterval { withAudioLock { items$.map { $0.duration$ }.reduce(0, +) } }

	/// Indicates whether the player has reached the end of the series of files.
	override var isAtEnd: Bool { withAudioLock { !items$.indices.contains(lastKnownIndex$) } }


	/// Adds a file player to the queue. Can be done at any time during playback or not. Queue player creates FilePlayer objects internally, meaning that `url` can only point to a local file. Returns `false` if there was an error opening the audio file.
	func addFile(url: URL) -> Bool {
		guard let player = FilePlayer(url: url, format: format, isEnabled: true) else {
			return false
		}
		withAudioLock {
			items$.append(player)
		}
		return true
	}


	/// Creates a queue player node. The `format argument should be the same as the current system output's format which you can obtain via `System`'s `.streamFormat` property.
	init(format: StreamFormat, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.format = format
		super.init(isEnabled: isEnabled, delegate: delegate)
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
			// Note that we bypass the usual rendering call _internalPull(). This is a bit dangerous in case changes are made in Node or FilePlayer. But in any case the player objects are fully managed by QueuePlayer so we go straight to what we need:
			withAudioLock {
				player._willRender$()
			}
			framesWritten += player.read(frameCount: frameCount, buffers: buffers, offset: framesWritten)
			if framesWritten >= frameCount {
				break
			}
			_currentIndex += 1
		}

		if framesWritten < frameCount {
			isEnabled = false
			didEndPlayingAsync()
		}
		else {
			didPlaySomeAsync()
		}

		withAudioLock {
			lastKnownIndex$ = _currentIndex
		}

		return noErr
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
		get {
			items$[..<lastKnownIndex$].map { $0.duration$ }.reduce(0, +)
				+ (items$.indices.contains(lastKnownIndex$) ? items$[lastKnownIndex$].time$ : 0)
		}
		set {
			var time = newValue
			for i in items$.indices {
				let item = items$[i]
				if time == 0 {
					// succeeding item, reset to 0
					item.time$ = 0
				}
				else if time >= item.duration$ {
					// preceding item, do nothing
					time -= item.duration$
				}
				else {
					// an item that should become current
					currentIndex$ = i
					item.time$ = time
					time = 0
				}
			}
		}
	}


	private let format: StreamFormat

	private var items$: [FilePlayer] = []
	private var _items: [FilePlayer] = []
	private var lastKnownIndex$: Int = 0
	private var currentIndex$: Int?
	private var _currentIndex: Int = 0
}


// MARK: - MemoryPlayer

class MemoryPlayer: Player {

	let data: AudioData

	override var time: TimeInterval { data.time }
	override var duration: TimeInterval { data.duration }
	override var isAtEnd: Bool { data.isAtEnd }


	init(data: AudioData, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.data = data
		super.init(isEnabled: isEnabled, delegate: delegate)
	}


	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		let result = data.read(frameCount: frameCount, buffers: buffers, offset: 0)
		if result < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: result)
			isEnabled = false
			didEndPlayingAsync()
		}
		else {
			didPlaySomeAsync()
		}
		return noErr
	}
}
