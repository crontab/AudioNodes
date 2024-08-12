//
//  Player.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 11.08.24.
//

import Foundation


@AudioActor
protocol PlayerDelegate: AnyObject {
	func player(_ player: Player, isAtFramePosition position: Int)
	func playerDidEndPlaying(_ player: Player)
}


class Player: Node {

	@AudioActor
	var time: TimeInterval {
		get {
			Double(prevKnownPlayhead) / file.sampleRate
		}
		set {
			withAudioLock {
				playhead$ = Int(newValue * file.sampleRate)
			}
		}
	}


	@AudioActor
	var duration: TimeInterval {
		Double(file.estimatedTotalFrames) / file.sampleRate
	}


	init?(url: URL, sampleRate: Double, isStereo: Bool, delegate: PlayerDelegate? = nil) {
		guard let file = AsyncAudioFileReader(url: url, sampleRate: sampleRate, isStereo: isStereo) else {
			return nil
		}
		self.file = file
		self.delegate = delegate
		super.init(isEnabled: false)
		prepopulateCache(position: 0)
	}


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var framesCopied: Int = 0
		var reachedEnd = false

		while framesCopied < frameCount {
			guard let block = file._blockAt(position: _playhead) else {
				// Assuming this is a cache miss (or i/o error) but not an end of file; can also happen if the playhead was moved significantly, so we'll play silence until the cache is filled again
				prepopulateCache(position: _playhead)
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
			prepopulateCache(position: _playhead)
			_didPlaySome(until: _playhead)
		}

		return noErr
	}


	@AudioActor private var prevKnownPlayhead: Int = 0
	@AudioActor private var prevDelegatePlayhead: Int = 0

	func _didPlaySome(until playhead: Int) {
		let file = file
		let delegate = delegate
		Task.detached { @AudioActor in
			self.prevKnownPlayhead = playhead
			guard let delegate else { return }
			let delta = Int(file.sampleRate / 25) // 25 fps update rate
			guard abs(playhead - self.prevDelegatePlayhead) > delta else { return }
			self.prevDelegatePlayhead = playhead
			delegate.player(self, isAtFramePosition: playhead)
		}
	}


	func _didEndPlaying(at playhead: Int, frameCount: Int, buffers: AudioBufferListPtr) {
		let file = file
		let delegate = delegate
		Task.detached { @AudioActor in
			self.prevKnownPlayhead = file.estimatedTotalFrames
			self.prevDelegatePlayhead = file.estimatedTotalFrames
			guard let delegate else { return }
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
			prepopulateCache(position: playhead)
		}
	}


	// Private

	private func prepopulateCache(position: Int) {
		let file = file
		Task.detached { @AudioFileActor in
			file.prepopulate(position: position)
		}
	}


	private let file: AsyncAudioFileReader
	private weak var delegate: PlayerDelegate?

	private var playhead$: Int?
	private var _playhead: Int = 0
}
