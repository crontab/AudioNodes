//
//  AudioState.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


@MainActor
class AudioState: ObservableObject, PlayerDelegate {

	@Published var isRunning: Bool = false {
		didSet {
			guard isRunning != oldValue else { return }
			if !isInitialized {
				isInitialized = true
				root.buses[0].connect(player)
			}
			if isRunning {
				Task {
					system.start()
					await system.smoothConnect(root)
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


	@Published var isPlaying: Bool = false {
		didSet {
			player.isEnabled = isPlaying
		}
	}


	@Published var playerTimePosition: TimeInterval = 0


	func player(_ player: Player, isAtFramePosition position: Int) {
		let time = player.time
		Task.detached { @MainActor in
			self.playerTimePosition = time
		}
	}


	func playerDidEndPlaying(_ player: Player) {
		Task.detached { @MainActor in
			self.isPlaying = false
		}
	}


	private var isInitialized: Bool = false
	private lazy var system = System(isStereo: true)
	private lazy var root: Mixer = .init(busCount: 1)
	private lazy var player = Player(url: fileUrl, sampleRate: system.systemFormat.sampleRate, isStereo: system.systemFormat.isStereo, delegate: self)!
}
