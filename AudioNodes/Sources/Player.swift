//
//  Player.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation


/// Player feedback delegate; used with both `FilePlayer` and `QueuePlayer`.
@MainActor
public protocol PlayerDelegate: AnyObject {

	/// Called by a player node approximately every 10ms. In GUI apps, make sure you reduce the frequency of UI updates since updating them at 100fps may lead to interruptions in audio playback and other undesirable effects. The method is executed on `MainActor`. This method is also called at the end of a playback just before a call to `playerDidEndPlaying()`.
	func player(_ player: Player, isAt time: TimeInterval)

	/// Called when a given player finishes the playback. Executed on `MainActor`.
	func playerDidEndPlaying(_ player: Player)
}


// MARK: - Abstract Player

/// Abstract node that defines the most basic player interface. Passed as an argument in `PlayerDelegate` methods; also FilePlayer, QueuePlayer and AudioData conform to this protocol.
open class Player: Source, @unchecked Sendable {
	public var time: TimeInterval {
		get { 0 }
		set { Abstract() }
	}
	public var duration: TimeInterval { 0 }
	public var isAtEnd: Bool { true }
	public func reset() { time = 0 }

	public init(isEnabled: Bool, delegate: PlayerDelegate?) {
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}

	final func didPlaySomeAsync() {
		guard let delegate else { return }
		Task.detached { @MainActor in
			delegate.player(self, isAt: self.time)
		}
	}

	final func didEndPlayingAsync() {
		guard let delegate else { return }
		Task.detached { @MainActor in
			delegate.player(self, isAt: self.duration)
			delegate.playerDidEndPlaying(self)
		}
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr, filled: inout Bool) {
		_read(frameCount: frameCount, buffers: buffers, offset: 0)
		filled = true
	}

	@discardableResult
	func _read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		// This method is called directly from QueuePlayer, i.e. bypassing the usual rendering chain; it's because QueuePlayer needs an extra argument `offset`.
		Abstract()
	}

	private weak var delegate: PlayerDelegate?
}


// MARK: - FilePlayer

/// Loads and plays an audio file; backed by the ExtAudioFile\* system interface. For each file that you want to play you create a separate FilePlayer node. This component uses a fixed amount of memory regarless of the file size; it employs smart look-ahead buffering.
/// You normally use the `isEnabled` property to start and stop the playback. When disabled, this node returns silence to the upstream nodes.
/// Once end of file is reached, `isEnable` flips to `false` automatically. You can restart the playback by setting `time` to `0` and enabling the node again.
/// You can pass a delegate to the constructor of `FilePlayer`; your delegate's overridden methods should assume being executed on `MainActor`.
open class FilePlayer: Player, @unchecked Sendable {

	/// Get or set the current time within the file. The granularity is approximately 10ms.
	public override var time: TimeInterval {
		get { Double(lastKnownPlayhead$) / file.format.sampleRate }
		set { playhead$ = Int(newValue * file.format.sampleRate).clamped(to: 0...file.estimatedTotalFrames) }
	}

	/// Returns the total duration of the audio file. If the system sampling rate is the same as the file's own then the value is highly accurate; however if it's not then this value may be slightly off due to floating point arithmetic quirks. Most of the time the inaccuracy may be ignored in your code.
	public override var duration: TimeInterval { file.estimatedDuration } // no need for a lock

	/// Indicates whether end of file was reached while playing the file.
	public override var isAtEnd: Bool { withAudioLock { lastKnownPlayhead$ == file.estimatedTotalFrames } }

	public func setAtEnd() { withAudioLock { playhead$ = file.estimatedTotalFrames } }

	public var format: StreamFormat { file.format }

	/// Creates a file player node for a given local audio file; note that remote URL's aren't supported.
	/// The `format` argument should be the same as the current system output's format which you can obtain from one of the  `System` objects.
	public init(url: URL, format: StreamFormat, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) throws {
		self.file = try AsyncAudioFileReader(url: url, format: format)
		super.init(isEnabled: isEnabled, delegate: delegate)
		prepopulateCacheAsync(position: 0)
	}


	// Internal

	override func _read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
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
			withAudioLock {
				lastKnownPlayhead$ = file.estimatedTotalFrames
			}
			// Avoid duplicate calls to didEndPlayingAsync() by checking _isEnabled: when disabling a node, it plays one more cycle by ramping data down.
			if _isEnabled {
				isEnabled = false
				didEndPlayingAsync()
			}
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
		if let playhead = playhead$.take() {
			_playhead = playhead
			prepopulateCacheAsync(position: playhead)
		}
	}


	// Private

	private func prepopulateCacheAsync(position: Int) {
		Task.detached { @AudioFileActor in
			self.file.prepopulate(position: position)
		}
	}


	private let file: AsyncAudioFileReader

	private var lastKnownPlayhead$: Int = 0
	private var playhead$: Int?
	private var _playhead: Int = 0
}


// MARK: - QueuePlayer

/// Meta-player that provides gapless playback of multiple player objects, including file players. This node treats a series of playable objects as a whole, it supports time positioning and `duration` within the whole. Think of Pink Floyd's *Wish You Were Here*, you absolutely *should* provide gapless playback for the entire album. Questions?
open class QueuePlayer: Player, @unchecked Sendable {

	/// Gets and sets the time position within the entire series of audio files.
	public override var time: TimeInterval {
		get { withAudioLock { time$ } }
		set { withAudioLock { time$ = newValue } }
	}

	/// Returns the total duration of the entire series of audio files.
	public override var duration: TimeInterval { items$.map { $0.duration }.reduce(0, +) } // no need for a lock

	/// Indicates whether the player has reached the end of the series of files.
	public override var isAtEnd: Bool { withAudioLock { !items$.indices.contains(lastKnownIndex$) } }

	/// Adds a file player to the queue. Can be done at any time during playback or not. `url` can only point to a local file. Throws an `AudioError` exception if there was an error opening the audio file. Returns the duration of the file on success.
	@discardableResult
	public func addFile(url: URL) throws -> TimeInterval {
		let player = try FilePlayer(url: url, format: format, isEnabled: true)
		withAudioLock {
			items$.append(player)
		}
		return player.duration
	}


	/// Adds a player to the queue. Can be done at any time during playback or not. The playhead of the player is reset to the start.
	public func addPlayer(_ player: Player) {
		player.reset()
		withAudioLock {
			items$.append(player)
		}
	}


	/// Creates a queue player node. The `format argument should be the same as the current system output's format which you can obtain from one of the  `System` objects.
	public init(format: StreamFormat, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.format = format
		super.init(isEnabled: isEnabled, delegate: delegate)
	}


	// Internal

	override func _read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		var framesWritten = offset

		while true {
			if !_items.indices.contains(_currentIndex) {
				FillSilence(frameCount: frameCount, buffers: buffers, offset: framesWritten)
				break
			}
			let player = _items[_currentIndex]
			// Note that we bypass the usual rendering call _internalPull(). This is a bit dangerous in case changes are made in Node or Player or any of its descendants. But in any case the player objects are fully managed by QueuePlayer so we go straight to what we need:
			player.withAudioLock {
				player._willRender$()
			}
			framesWritten += player._read(frameCount: frameCount, buffers: buffers, offset: framesWritten)
			if framesWritten >= frameCount {
				break
			}
			_currentIndex += 1
		}

		withAudioLock {
			lastKnownIndex$ = _currentIndex
		}

		if framesWritten < frameCount {
			if _isEnabled {
				isEnabled = false
				didEndPlayingAsync()
			}
		}
		else {
			didPlaySomeAsync()
		}

		return framesWritten - offset
	}


	override func _willRender$() {
		super._willRender$()
		_items = items$
		if let currentIndex = currentIndex$.take() {
			_currentIndex = currentIndex
		}
	}


	// Private

	private var time$: TimeInterval {
		get {
			items$[..<lastKnownIndex$].map { $0.duration }.reduce(0, +)
				+ (items$.indices.contains(lastKnownIndex$) ? items$[lastKnownIndex$].time : 0)
		}
		set {
			var time = newValue
			for i in items$.indices {
				let item = items$[i]
				if time == 0 {
					// succeeding item, reset to 0
					item.time = 0
				}
				else if time >= item.duration {
					// preceding item, do nothing
					time -= item.duration
				}
				else {
					// an item that should become current
					currentIndex$ = i
					item.time = time
					time = 0
				}
			}
		}
	}


	private let format: StreamFormat

	private var items$: [Player] = []
	private var _items: [Player] = []
	private var lastKnownIndex$: Int = 0
	private var currentIndex$: Int?
	private var _currentIndex: Int = 0
}


// MARK: - MemoryPlayer

open class MemoryPlayer: Player, @unchecked Sendable {

	public let data: AudioData
	public override var time: TimeInterval {
		get { data.time }
		set { data.time = newValue }
	}
	public override var duration: TimeInterval {
		get { data.duration }
		set { data.duration = newValue }
	}
	public override var isAtEnd: Bool { data.isAtEnd }
	public override func reset() { data.resetRead() }

	public init(data: AudioData, isEnabled: Bool = false, delegate: PlayerDelegate? = nil) {
		self.data = data
		super.init(isEnabled: isEnabled, delegate: delegate)
	}

	override func _read(frameCount: Int, buffers: AudioBufferListPtr, offset: Int) -> Int {
		let result = data.read(frameCount: frameCount, buffers: buffers, offset: offset)
		if result < frameCount {
			FillSilence(frameCount: frameCount, buffers: buffers, offset: result)
			if _isEnabled {
				isEnabled = false
				didEndPlayingAsync()
			}
		}
		else {
			didPlaySomeAsync()
		}
		return result
	}
}


// MARK: - Static async players

private class Coordinator: PlayerDelegate {
	var continuation: CheckedContinuation<Void, Error>?

	deinit { DLOG("Delegate: deinit") }

	func player(_ player: Player, isAt time: TimeInterval) { }

	func playerDidEndPlaying(_ player: Player) {
		continuation?.resume()
	}
}


extension FilePlayer {

	@MainActor
	public static func playAsync(_ url: URL, format: StreamFormat, driver: Source) async throws {
		let coordinator = Coordinator()
		try await withCheckedThrowingContinuation { continuation in
			coordinator.continuation = continuation
			do {
				let player = try FilePlayer(url: url, format: format, isEnabled: true, delegate: coordinator)
				driver.connectSource(player)
			}
			catch {
				continuation.resume(throwing: error)
			}
		}
		await driver.disconnectSource()
	}
}


extension MemoryPlayer {

	@MainActor
	public static func playAsync(_ data: AudioData, driver: Source) async throws {
		let coordinator = Coordinator()
		try await withCheckedThrowingContinuation { continuation in
			coordinator.continuation = continuation
			let player = MemoryPlayer(data: data, isEnabled: true, delegate: coordinator)
			driver.connectSource(player)
		}
		await driver.disconnectSource()
	}
}
