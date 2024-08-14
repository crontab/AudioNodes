//
//  Recorder.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 14.08.24.
//

import Foundation
import AudioToolbox


@AudioActor
protocol RecorderDelegate: AnyObject, Sendable {
	func recorder(_ recorder: Recorder, isAt time: TimeInterval)
	func recorderDidEndRecording(_ recorder: Recorder)
}


protocol Recorder: Sendable {
	var duration: TimeInterval { get }
	var isFull: Bool { get }
	var recorderDelegate: RecorderDelegate? { get }

	func stop()
	func write(frameCount: Int, buffers: AudioBufferListPtr) -> Int
}


extension Recorder {

	func didRecordSomeAsync() {
		guard let recorderDelegate else { return }
		Task.detached { @AudioActor in
			recorderDelegate.recorder(self, isAt: duration)
		}
	}

	func didEndRecordingAsync() {
		guard let recorderDelegate else { return }
		Task.detached { @AudioActor in
			recorderDelegate.recorder(self, isAt: duration)
			recorderDelegate.recorderDidEndRecording(self)
		}
	}
}


// MARK: - FileRecorder

class FileRecorder: Monitor, Recorder {

	var duration: TimeInterval { withAudioLock { Double(lastKnownPlayhead$) / file.format.sampleRate } }

	var isFull: Bool { withAudioLock { lastKnownPlayhead$ >= frameCapacity } }


	init?(url: URL, format: StreamFormat, fileSampleRate: Double, compressed: Bool = true, capacity: TimeInterval, delegate: RecorderDelegate? = nil, isEnabled: Bool = false) {
		guard let file = AudioFileWriter(url: url, format: format, fileSampleRate: fileSampleRate, compressed: compressed, async: true) else {
			return nil
		}
		self.file = file
		self.frameCapacity = Int(capacity * format.sampleRate)
		super.init(isEnabled: isEnabled)
	}


	// Internal

	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		write(frameCount: frameCount, buffers: buffers)
	}


	func stop() {
		isEnabled = false
	}


	@discardableResult
	func write(frameCount: Int, buffers: AudioBufferListPtr) -> Int {
		let toWrite = min(frameCount, frameCapacity - _playhead)
		if toWrite > 0, file.writeAsync(frameCount: toWrite, buffers: buffers) == nil {
			_playhead += toWrite
			withAudioLock {
				lastKnownPlayhead$ = _playhead
			}
			didRecordSomeAsync()
			return frameCount
		}
		else {
			isEnabled = false
			didEndRecordingAsync()
			return 0
		}
	}


	// Private

	var recorderDelegate: (any RecorderDelegate)?

	private let file: AudioFileWriter
	private let frameCapacity: Int

	private var _playhead: Int = 0
	private var lastKnownPlayhead$: Int = 0
}
