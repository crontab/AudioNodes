//
//  MainAudioState.swift
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation
import AVFAudio
import AudioNodes


private let FileSampleRate: Double = 48000

private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


@MainActor
final class MainAudioState: ObservableObject, PlayerDelegate, MeterDelegate, FFTMeterDelegate, RecorderDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isRunning != oldValue else { return }
			initializeOutputGraph()
			if isRunning {
				stereo.start()
				stereo.connectSource(mixer)
			}
			else {
				Task {
					await stereo.smoothDisconnect()
					stereo.stop()
				}
			}
		}
	}


	@Published var isOutputEnabled = true {
		didSet {
			guard !Globals.isPreview else { return }
			stereo.isEnabled = isOutputEnabled
		}
	}


	@Published var isInputEnabled = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isInputEnabled != oldValue else { return }
			if isInputEnabled {
				Task {
					if await stereo.requestInputAuthorization(), let input {
						initializeInputGraph()
						input.connectMonitor(inputMeter)
						input.isEnabled = true
					}
					else {
						isInputEnabled = false
					}
				}
			}
			else {
				input?.isEnabled = false
			}
		}
	}


	@Published var isPlaying: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isPlaying != oldValue else { return }
			guard let filePlayer else {
				isPlaying = false
				return
			}
			if isPlaying, filePlayer.isAtEnd {
				filePlayer.time = 0
			}
			filePlayer.isEnabled = isPlaying
		}
	}


	@Published var isRecording: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isRecording != oldValue else { return }
			if isRecording {
				isRecordingPlaying = false
				recorder.isEnabled = false
				recordingData.clear()
				recorderPosition = 0
				recorder.isEnabled = true
			}
			else {
				recorder.isEnabled = false
			}
		}
	}


	@Published var isRecordingPlaying: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isRecordingPlaying != oldValue else { return }
			if isRecordingPlaying {
				isRecording = false
				if recordingPlayer.isAtEnd {
					recordingPlayer.reset()
				}
			}
			recordingPlayer.isEnabled = isRecordingPlaying
		}
	}


	@Published var playerTimePosition: TimeInterval = 0
	@Published var recorderPosition: TimeInterval = 0

	@Published var outputGainLeft: Float = 0
	@Published var outputGainRight: Float = 0

	@Published var inputLevels: [Float] = []

	@Published var trackWaveform: Waveform?
	@Published var voiceWaveform: Waveform?


	func saveRecording(to url: URL) -> Bool {
		recordingData.writeToFile(url: url, fileSampleRate: FileSampleRate)
	}


	func loadFile(url: URL) async {
		if let filePlayer {
			filePlayer.isEnabled = false
			await mixer[.filePlayer].smoothDisconnect()
		}
		guard let newPlayer = FilePlayer(url: url, format: stereo.outputFormat, delegate: self) else {
			return
		}
		filePlayer = newPlayer
		mixer[.filePlayer].connectSource(newPlayer)
		playerTimePosition = 0
		resetInputGain()

		Task {
			guard let file = AudioFileReader(url: url, format: stereo.outputFormat) else {
				return
			}
			trackWaveform = Waveform.fromSource(file, ticksPerSec: 4)
		}
	}


	init() {
		guard !Globals.isPreview else { return }
		Self.activateAVAudioSession()
		if System.inputAuthorized {
			isInputEnabled = true
//			isVoiceEnabled = true // also enables input
		}
		Task {
			await loadFile(url: fileUrl)
		}
	}


	// MARK: - Player delegate

	func player(_ player: Player, isAt time: TimeInterval) {
		if player === self.filePlayer {
//				self.playerTimePosition = time
		}
		else if player === self.recordingPlayer {
		}
	}


	func playerDidEndPlaying(_ player: Player) {
		if player === self.filePlayer {
			self.isPlaying = false
		}
		else if player === self.recordingPlayer {
			self.isRecordingPlaying = false
		}
	}


	// MARK: - Recorder delegate

	private var previousRecPos: TimeInterval = 0

	func recorder(_ recorder: Recorder, isAt time: TimeInterval) {
		guard abs(time - previousRecPos) >= 0.25 else { return }
		previousRecPos = time
		recorderPosition = time
	}


	func recorderDidEndRecording(_ recorder: Recorder) {
		isRecording = false
	}


	// MARK: - Meter delegate

	private let declineAmount: Float = 0.05
	private var prevOutLeft: Float = 0, prevOutRight: Float = 0

	func meterDidUpdateGains(_ meter: Meter, left: Float, right: Float) {
		let newLeft = normalizeDB(left)
		let newRight = normalizeDB(right)
		precondition((0...1).contains(newLeft) && (0...1).contains(newRight))

		if meter === outputMeter {
			prevOutLeft = max(newLeft, prevOutLeft - declineAmount)
			prevOutRight = max(newRight, prevOutRight - declineAmount)
			outputGainLeft = prevOutLeft
			outputGainRight = prevOutRight
		}
	}


	func fftMeterDidUpdateLevels(_ fftMeter: FFTMeter, levels: [Float]) {
		let newLevels = levels.map { normalizeDB($0, floor: -80) }
		if inputLevels.count != newLevels.count {
			inputLevels = Array(repeating: SILENCE_DB, count: newLevels.count)
		}
		for i in 0..<newLevels.count {
			inputLevels[i] = max(0.1, newLevels[i], inputLevels[i] - declineAmount)
		}
	}


	private func resetInputGain() {
		outputGainLeft = 0
		outputGainRight = 0
		prevOutLeft = 0
		prevOutRight = 0
		inputLevels = []
	}


	private func normalizeDB(_ db: Float, floor: Float = -50) -> Float {
		1 - (max(db, floor) / floor)
	}


	// MARK: - Private part

	private enum InChannel: Int, CaseIterable {
		case filePlayer
		case recordingPlayer
	}

	private var isOutputInitialized: Bool = false

	private func initializeOutputGraph() {
		guard !isOutputInitialized else { return }
		isOutputInitialized = true
		mixer[.recordingPlayer].connectSource(recordingPlayer)
		mixer.connectMonitor(outputMeter)
	}


	private var isInputInitialized: Bool = false

	private func initializeInputGraph() {
		guard !isInputInitialized else { return }
		isInputInitialized = true
		inputMeter.connectMonitor(recorder)
	}


	private lazy var stereo = Stereo() // with default hardware sampling rate
	private var input: System.Input? { stereo.input }

	private lazy var mixer: EnumMixer<InChannel> = .init(format: stereo.outputFormat)
	private var filePlayer: FilePlayer?

	private lazy var recordingData = AudioData(durationSeconds: 30, format: stereo.inputFormat)
	private lazy var recorder = MemoryRecorder(data: recordingData, delegate: self)
	private lazy var recordingPlayer = MemoryPlayer(data: recordingData, delegate: self)

	private lazy var outputMeter = Meter(format: stereo.outputFormat, delegate: self)
	private lazy var inputMeter = FFTMeter(format: stereo.inputFormat, delegate: self)


	private static func activateAVAudioSession() {
		try! AVAudioSession.sharedInstance().setActive(false)
		try! AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowAirPlay, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
		try! AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
	}
}
