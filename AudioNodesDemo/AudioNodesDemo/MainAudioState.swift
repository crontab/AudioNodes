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
				if let mixer {
					system.connectSource(mixer)
				}
			}
			else {
				isInputEnabled = false
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


	var isFilePlaying: Bool {
		get {
			filePlayer?.isEnabled ?? false
		}
		set {
			guard !Globals.isPreview else { return }
			guard let filePlayer else { return }
			if newValue, filePlayer.isAtEnd {
				filePlayer.time = 0
			}
			filePlayer.isEnabled = newValue
		}
	}


	var isRecording: Bool {
		get {
			recorder != nil
		}
		set {
			guard !Globals.isPreview else { return }
			guard let input, let inputMeter else { return }
			if newValue {
				isRecordingPlaying = false
				recorderPosition = 0
				if let recorder = try? FileRecorder(url: tempFileURL, format: input.inputFormat, fileSampleRate: FileSampleRate, capacity: 30 * 60, isEnabled: true, delegate: self) {
					print("Recording to \(tempFileURL)")
					self.recorder = recorder
					inputMeter.connectMonitor(recorder)
				}
			}
			else {
				inputMeter.disconnectMonitor()
				recorder = nil
			}
		}
	}


	var isRecordingPlaying: Bool {
		get {
			recordingPlayer != nil
		}
		set {
			guard !Globals.isPreview else { return }
			guard let mixer else { return }
			if newValue {
				isRecording = false
				if let player = try? FilePlayer(url: tempFileURL, format: system.outputFormat, isEnabled: true, delegate: self) {
					self.recordingPlayer = player
					mixer[.recordingPlayer].connectSource(player)
				}
			}
			else {
				recordingPlayer = nil
				Task {
					await mixer[.recordingPlayer].disconnectSource()
				}
			}
		}
	}


	@Published var playerTimePosition: TimeInterval = 0
	@Published var recorderPosition: TimeInterval = 0

	@Published var outputGainLeft: Float = 0
	@Published var outputGainRight: Float = 0

	@Published var inputLevels: [Float] = []

	@Published var trackWaveform: Waveform?


	func loadFile(url: URL) async throws {
		guard let mixer else { return }
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
		if player === self.recordingPlayer {
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
	private var prevOutLeft: Float = 0
	private var prevOutRight: Float = 0

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
		let mixer = EnumMixer<InChannel>(format: system.outputFormat)
		let outputMeter = Meter(format: system.outputFormat, delegate: self)
		mixer.connectMonitor(outputMeter)
		self.mixer = mixer
		self.outputMeter = outputMeter
	}


	private var isInputInitialized: Bool = false

	private func initializeInputGraph(input: System.Input) {
		guard !isInputInitialized else { return }
		isInputInitialized = true
		let inputMeter = FFTMeter(format: input.inputFormat, delegate: self)
		input.connectMonitor(inputMeter)
		self.inputMeter = inputMeter
	}


//	private var system = Mono()
	private let system = Stereo()
	private var input: System.Input? { system.input }

	private var mixer: EnumMixer<InChannel>?
	private var filePlayer: FilePlayer?

	private let tempFileURL = Globals.tempFileURL(ext: "m4a")
	private var recorder: FileRecorder?
	private var recordingPlayer: FilePlayer?

	private var outputMeter: Meter?
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
