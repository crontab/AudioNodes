//
//  AudioState.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation
import AVFAudio


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!

private func outUrl(_ name: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "../").appendingPathComponent(name) }



@MainActor
final class AudioState: ObservableObject, PlayerDelegate, MeterDelegate, RecorderDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard isRunning != oldValue else { return }
			initializeOutputGraph()
			if isRunning {
				system.start()
				system.connectSource(mixer)
			}
			else {
				Task {
					await system.smoothDisconnect()
					system.stop()
				}
			}
		}
	}


	@Published var isOutputEnabled = true {
		didSet {
			system.isEnabled = isOutputEnabled
		}
	}


	@Published var isInputEnabled = false {
		didSet {
			guard isInputEnabled != oldValue else { return }
			if isInputEnabled {
				Task {
					if await system.requestInputAuthorization(), let input = system.input {
						initializeInputGraph()
						input.isEnabled = true
					}
					else {
						isInputEnabled = false
					}
				}
			}
			else {
				system.input?.isEnabled = false
			}
		}
	}


	@Published var isPlaying: Bool = false {
		didSet {
			if isPlaying, player.isAtEnd {
				player.time = 0
			}
			player.isEnabled = isPlaying
		}
	}


	@Published var isRecording: Bool = false {
		didSet {
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

	@Published var inputGain: Float = 0


	init() {
		guard !Globals.isPreview else { return }
		Self.activateAVAudioSession()
		if System.inputAuthorized {
			isInputEnabled = true
		}
	}


	// MARK: - Player delegate

	func player(_ player: Player, isAt time: TimeInterval) {
		Task { @MainActor in
			if player === self.player {
//				self.playerTimePosition = time
			}
			else if player === self.recordingPlayer {
			}
		}
	}


	func playerDidEndPlaying(_ player: Player) {
		Task { @MainActor in
			if player === self.player {
				self.isPlaying = false
			}
			else if player === self.recordingPlayer {
				self.isRecordingPlaying = false
			}
		}
	}


	// MARK: - Recorder delegate

	@AudioActor
	private var previousRecPos: TimeInterval = 0

	func recorder(_ recorder: Recorder, isAt time: TimeInterval) {
		guard abs(time - previousRecPos) >= 0.25 else { return }
		previousRecPos = time
		Task { @MainActor in
			recorderPosition = time
		}
	}


	func recorderDidEndRecording(_ recorder: Recorder) {
		Task { @MainActor in
			isRecording = false
		}
	}


	// MARK: - Meter delegate

	func meterDidUpdateGains(_ meter: Meter, left: Float, right: Float) {
		Task { @MainActor in
			func normalizeDB(_ db: Float) -> Float { 1 - (max(db, -50) / -50) }

			let newLeft = normalizeDB(left)
			let newRight = normalizeDB(right)

			if meter === outputMeter {
				prevOutLeft = max(newLeft, prevOutLeft - declineAmount)
				prevOutRight = max(newRight, prevOutRight - declineAmount)
				outputGainLeft = prevOutLeft
				outputGainRight = prevOutRight
			}
			else if meter === inputMeter {
				prevInLeft = max(newLeft, prevInLeft - declineAmount)
				inputGain = prevInLeft
			}
		}
	}


	// MARK: - Private part

	private func initializeOutputGraph() {
		guard !isOutputInitialized else { return }
		isOutputInitialized = true
		mixer.buses[0].connectSource(player)
		mixer.buses[1].connectSource(recordingPlayer)
		mixer.connectMonitor(outputMeter)
	}


	private func initializeInputGraph() {
		guard !isInputInitialized else { return }
		isInputInitialized = true
		inputMeter.connectMonitor(recorder)
		system.input?.connectMonitor(inputMeter)
	}


	private var isOutputInitialized: Bool = false
	private var isInputInitialized: Bool = false

	private lazy var system = System(isStereo: true)
	private lazy var mixer: Mixer = .init(format: system.streamFormat, busCount: 2)
	private lazy var player = FilePlayer(url: fileUrl, format: system.streamFormat, delegate: self)!

	private lazy var recordingData = AudioData(durationSeconds: 30, format: system.streamFormat)
	private lazy var recorder = MemoryRecorder(data: recordingData, delegate: self)
	private lazy var recordingPlayer = MemoryPlayer(data: recordingData, delegate: self)

	private lazy var outputMeter = Meter(format: system.streamFormat, delegate: self)
	private lazy var inputMeter = Meter(format: system.streamFormat, delegate: self)

	private var prevOutLeft: Float = 0, prevOutRight: Float = 0
	private var prevInLeft: Float = 0
	private let declineAmount: Float = 0.05


	private static func activateAVAudioSession() {
		try! AVAudioSession.sharedInstance().setActive(false)
		try! AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowAirPlay, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
		try! AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
	}
}
