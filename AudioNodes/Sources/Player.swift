//
//  Player.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation


@AudioActor
protocol PlayerDelegate: AnyObject, Sendable {
	func player(_ player: Player, isAtFramePosition position: Int)
	func playerDidEndPlaying(_ player: Player)
}


class Player: Node {

	var time: TimeInterval {
		get {
			withAudioLock { 
				Double(lastKnownPlayhead$) / file.sampleRate
			}
		}
		set {
			withAudioLock {
				playhead$ = Int(newValue * file.sampleRate)
			}
		}
	}


	var duration: TimeInterval {
		Double(file.estimatedTotalFrames) / file.sampleRate
	}


	var isAtEnd: Bool {
		withAudioLock { 
			lastKnownPlayhead$ == file.estimatedTotalFrames // always correct because prevKnownPlayhead is assigned the same value in _didEndPlaying()
		}
	}


	init?(url: URL, sampleRate: Double, isStereo: Bool, delegate: PlayerDelegate? = nil) {
		guard let file = AsyncAudioFileReader(url: url, sampleRate: sampleRate, isStereo: isStereo) else {
			return nil
		}
		self.file = file
		self.delegate = delegate
		super.init(isEnabled: false)
		prepopulateCacheAsync(position: 0)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var framesCopied: Int = 0
		var reachedEnd = false

		while framesCopied < frameCount {
			guard let block = file._blockAt(position: _playhead) else {
				// Assuming this is a cache miss (or i/o error) but not an end of file; can also happen if the playhead was moved significantly, so we'll play silence until the cache is filled again
				prepopulateCacheAsync(position: _playhead)
				break
			}
			let copied = Copy(from: block.buffers, to: buffers, fromOffset: _playhead - block.offset, toOffset: framesCopied, framesMax: frameCount - framesCopied)
			if copied == 0 {
				// Gapless playing should happen here, e.g. this buffer should be passed to the next player in the queue
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
			_didEndPlaying(at: _playhead, frameCount: frameCount, buffers: buffers)
		}
		else {
			prepopulateCacheAsync(position: _playhead)
			_didPlaySome(until: _playhead)
		}

		return noErr
	}


	@AudioActor private var prevDelegatePlayhead: Int = 0

	private func _didPlaySome(until playhead: Int) {
		withAudioLock {
			lastKnownPlayhead$ = playhead
		}
		Task.detached { @AudioActor in
			guard let delegate = self.delegate else { return }
			let delta = Int(self.file.sampleRate / 25) // 25 fps update rate
			guard abs(playhead - self.prevDelegatePlayhead) > delta else { return }
			self.prevDelegatePlayhead = playhead
			delegate.player(self, isAtFramePosition: playhead)
		}
	}


	private func _didEndPlaying(at playhead: Int, frameCount: Int, buffers: AudioBufferListPtr) {
		isEnabled = false
		withAudioLock {
			lastKnownPlayhead$ = file.estimatedTotalFrames
		}
		Task.detached { @AudioActor in
			self.prevDelegatePlayhead = self.file.estimatedTotalFrames
			guard let delegate = self.delegate else { return }
			delegate.playerDidEndPlaying(self)
		}
	}


	override func willConnect$(with format: StreamFormat) {
		Assert(format.sampleRate == file.sampleRate && format.isStereo == file.isStereo, 51050)
		super.willConnect$(with: format)
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
}
