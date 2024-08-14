//
//  AudioState.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


@MainActor
final class AudioState: ObservableObject, PlayerDelegate, MeterDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard isRunning != oldValue else { return }
			initializeGraph()
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


	@Published var isPlaying: Bool = false {
		didSet {
			if isPlaying, player.isAtEnd {
				player.time = 0
			}
			player.isEnabled = isPlaying
		}
	}


	@Published var playerTimePosition: TimeInterval = 0

	@Published var normalizedOutputGainLeft: Float = 0
	@Published var normalizedOutputGainRight: Float = 0


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
				normalizedOutputGainLeft = prevOutLeft
				normalizedOutputGainRight = prevOutRight
			}
		}
	}


	private func initializeGraph() {
		guard !isInitialized else { return }
		isInitialized = true
		root.buses[0].connect(player)
		root.connectMonitor(outputMeter)
	}


	private var isInitialized: Bool = false
	private lazy var system = System(isStereo: true)
	private lazy var root: Mixer = .init(format: system.streamFormat, busCount: 1)
	private lazy var player = FilePlayer(url: fileUrl, format: system.streamFormat, delegate: self)!
	private lazy var outputMeter = Meter(format: system.streamFormat, delegate: self)

	private var prevOutLeft: Float = 0, prevOutRight: Float = 0
	private let declineAmount: Float = 0.05
}
