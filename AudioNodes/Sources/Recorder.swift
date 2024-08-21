//
//  Recorder.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 14.08.24.
//

import Foundation
import AudioToolbox


@MainActor
protocol RecorderDelegate: AnyObject, Sendable {
	func recorder(_ recorder: Recorder, isAt time: TimeInterval)
	func recorderDidEndRecording(_ recorder: Recorder)
}


class Recorder: Monitor {
	var capacity: TimeInterval { 0 }
	var duration: TimeInterval { 0 }
	var isFull: Bool { true }

	init(isEnabled: Bool, delegate: RecorderDelegate?) {
		self.delegate = delegate
		super.init(isEnabled: isEnabled)
	}

	final func didRecordSomeAsync() {
		guard let delegate else { return }
		Task.detached { @MainActor in
			delegate.recorder(self, isAt: self.duration)
		}
	}

	final func didEndRecordingAsync() {
		guard let delegate else { return }
		Task.detached { @MainActor in
			delegate.recorder(self, isAt: self.duration)
			delegate.recorderDidEndRecording(self)
		}
	}

	private weak var delegate: RecorderDelegate?
}


// MARK: - FileRecorder

class FileRecorder: Recorder {

	override var capacity: TimeInterval { .greatestFiniteMagnitude } // TODO: available disk space?

	override var duration: TimeInterval { withAudioLock { Double(lastKnownPlayhead$) / file.format.sampleRate } }

	override var isFull: Bool { withAudioLock { lastKnownPlayhead$ >= frameCapacity } }


	init?(url: URL, format: StreamFormat, fileSampleRate: Double, compressed: Bool = true, capacity: TimeInterval, delegate: RecorderDelegate? = nil, isEnabled: Bool = false) {
		guard let file = AudioFileWriter(url: url, format: format, fileSampleRate: fileSampleRate, compressed: compressed, async: true) else {
			return nil
		}
		self.file = file
		self.frameCapacity = Int(capacity * format.sampleRate)
		super.init(isEnabled: isEnabled, delegate: delegate)
	}


	func stop() {
		isEnabled = false
	}


	// Internal

	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		let toWrite = min(frameCount, frameCapacity - _playhead)
		if toWrite > 0, file.writeAsync(frameCount: toWrite, buffers: buffers) == noErr {
			_playhead += toWrite
			withAudioLock {
				lastKnownPlayhead$ = _playhead
			}
			didRecordSomeAsync()
		}
		else {
			isEnabled = false
			didEndRecordingAsync()
		}
	}


	// Private

	private let file: AudioFileWriter
	private let frameCapacity: Int

	private var _playhead: Int = 0
	private var lastKnownPlayhead$: Int = 0
}


// MARK: - MemoryRecorder

class MemoryRecorder: Recorder {

	let data: AudioData

	override var capacity: TimeInterval { data.capacity }
	override var duration: TimeInterval { data.duration }
	override var isFull: Bool { data.isFull }


	init(data: AudioData, isEnabled: Bool = false, delegate: RecorderDelegate? = nil) {
		self.data = data
		super.init(isEnabled: isEnabled, delegate: delegate)
	}


	override func _monitor(frameCount: Int, buffers: AudioBufferListPtr) {
		let result = data.write(frameCount: frameCount, buffers: buffers)
		if result < frameCount {
			isEnabled = false
			didEndRecordingAsync()
		}
		else {
			didRecordSomeAsync()
		}
	}
}
