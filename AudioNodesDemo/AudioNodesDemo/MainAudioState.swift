//
//  MainAudioState.swift
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation
import AVFAudio
import AudioNodes


private let FileSampleRate: Double = 44100

private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


@MainActor
final class MainAudioState: ObservableObject, PlayerDelegate, MeterDelegate, FFTMeterDelegate, RecorderDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isRunning != oldValue else { return }
			initializeOutputGraph()
			if isRunning {
				system.start()
				system.connectSource(mixer)
			}
			else {
				Task {
					await system.disconnectSource()
					system.stop()
				}
			}
		}
	}


	@Published var isOutputEnabled = true {
		didSet {
			guard !Globals.isPreview else { return }
			system.isEnabled = isOutputEnabled
		}
	}


	@Published var isInputEnabled = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isInputEnabled != oldValue else { return }
			if isInputEnabled {
				Task {
					if await system.requestInputAuthorization(), let input {
						initializeInputGraph(input: input)
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
				recorder?.isEnabled = false
				recordingData?.clear()
				recorderPosition = 0
				recorder?.isEnabled = true
			}
			else {
				recorder?.isEnabled = false
			}
		}
	}


	@Published var isRecordingPlaying: Bool = false {
		didSet {
			guard !Globals.isPreview else { return }
			guard isRecordingPlaying != oldValue else { return }
			if isRecordingPlaying {
				isRecording = false
				if recordingPlayer?.isAtEnd ?? false {
					recordingPlayer?.reset()
				}
			}
			recordingPlayer?.isEnabled = isRecordingPlaying
		}
	}


	@Published var playerTimePosition: TimeInterval = 0
	@Published var recorderPosition: TimeInterval = 0

	@Published var outputGainLeft: Float = 0
	@Published var outputGainRight: Float = 0

	@Published var inputLevels: [Float] = []

	@Published var trackWaveform: Waveform?


	func saveRecording(to url: URL) throws {
		try recordingData?.writeToFile(url: url, fileSampleRate: FileSampleRate)
	}


	func loadFile(url: URL) async throws {
		if let filePlayer {
			filePlayer.isEnabled = false
			await mixer[.filePlayer].disconnectSource()
		}
		let newPlayer = try FilePlayer(url: url, format: system.outputFormat, delegate: self)
		filePlayer = newPlayer
		mixer[.filePlayer].connectSource(newPlayer)
		playerTimePosition = 0
		resetInputGain()

		Task {
			let file = try AudioFileReader(url: url, format: system.outputFormat)
			trackWaveform = try Waveform.fromSource(file, ticksPerSec: 4)
		}
	}


	init() {
		guard !Globals.isPreview else { return }
		Self.activateAVAudioSession()
		if System.inputAuthorized {
			isInputEnabled = true
		}
		Task {
			try await loadFile(url: fileUrl)
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
//		mixer[.recordingPlayer].connectSource(recordingPlayer)
		mixer.connectMonitor(outputMeter)
	}


	private var isInputInitialized: Bool = false

	private func initializeInputGraph(input: System.Input) {
		guard !isInputInitialized else { return }
		isInputInitialized = true
		let recordingData = AudioData(durationSeconds: 30, format: input.inputFormat)
		let recorder = MemoryRecorder(data: recordingData, delegate: self)
		let recordingPlayer = MemoryPlayer(data: recordingData, delegate: self)
		let inputMeter = FFTMeter(format: input.inputFormat, delegate: self)
		inputMeter.connectMonitor(recorder)
		input.connectMonitor(inputMeter)

		self.recordingData = recordingData
		self.recorder = recorder
		self.recordingPlayer = recordingPlayer
		self.inputMeter = inputMeter
	}


//	private lazy var system = Mono()
	private lazy var system = Stereo()
	private var input: System.Input? { system.input }

	private lazy var mixer: EnumMixer<InChannel> = .init(format: system.outputFormat)
	private var filePlayer: FilePlayer?

	private var recordingData: AudioData?
	private var recorder: MemoryRecorder?
	private var recordingPlayer: MemoryPlayer?

	private lazy var outputMeter = Meter(format: system.outputFormat, delegate: self)
	private var inputMeter: FFTMeter?


	private static func activateAVAudioSession() {
		guard !Globals.isPreview else { return }
#if os(iOS)
		try! AVAudioSession.sharedInstance().setActive(false)
		try! AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
		try! AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
#endif
	}
}
