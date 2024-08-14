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
final class AudioState: ObservableObject, PlayerDelegate, MeterDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard isRunning != oldValue else { return }
			initializeOutputGraph()
			if isRunning {
				Task {
					system.start()
					system.connect(root)
				}
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
		}
	}


	@Published var playerTimePosition: TimeInterval = 0

	@Published var outputGainLeft: Float = 0
	@Published var outputGainRight: Float = 0

	@Published var inputGain: Float = 0


	init() {
		guard !Globals.isPreview else { return }
		Self.activateAVAudioSession()
	}


	func player(_ player: Player, isAt time: TimeInterval) {
//		let time = player.time
//		Task { @MainActor in
//			self.playerTimePosition = time
//		}
	}


	func playerDidEndPlaying(_ player: Player) {
		Task { @MainActor in
			self.isPlaying = false
		}
	}


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


	private func initializeOutputGraph() {
		guard !isOutputInitialized else { return }
		isOutputInitialized = true
		root.buses[0].connect(player)
		root.connectMonitor(outputMeter)
	}


	private func initializeInputGraph() {
		guard !isInputInitialized else { return }
		isInputInitialized = true
		system.input?.connectMonitor(inputMeter)
	}


	private var isOutputInitialized: Bool = false, isInputInitialized: Bool = false
	private lazy var system = System(isStereo: true)
	private lazy var root: Mixer = .init(format: system.streamFormat, busCount: 1)
	private lazy var player = FilePlayer(url: fileUrl, format: system.streamFormat, delegate: self)!
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
