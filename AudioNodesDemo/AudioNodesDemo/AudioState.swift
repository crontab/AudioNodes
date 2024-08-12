//
//  AudioState.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


class AudioState: ObservableObject {

	@Published var isRunning: Bool = false {
		didSet {
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


	init() {
		root.buses[0].connect(player)
	}


	private lazy var system = System(isStereo: true)
	private lazy var root: Mixer = .init(busCount: 1)
	private lazy var player = Player(url: fileUrl, sampleRate: system.systemFormat.sampleRate, isStereo: system.systemFormat.isStereo)!
}
