//
//  CLITest.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import AVFoundation
import AudioToolbox


@AudioActor
extension System {

	func testSine() async {
		print("--- ", #function)
		let sine = SineGenerator(freq: 440)
		await smoothConnect(sine)
		await Sleep(1)
		sine.isEnabled = false
		await Sleep(1)
		sine.frequency = 480
		sine.isEnabled = true
		await Sleep(1)
		await smoothDisconnect()
		await Sleep(1)
	}

	func testMixer() async {
		print("--- ", #function)
		let sine1 = SineGenerator(freq: 440)
		let sine2 = SineGenerator(freq: 480)
		let mixer = Mixer(busCount: 2)
		mixer.buses[0].connect(sine1)
		mixer.buses[1].connect(sine2)
		connect(mixer)
		await Sleep(1)
		mixer.buses[0].setVolume(0.5, duration: 1)
		await Sleep(1)
		mixer.buses[0].setVolume(1, duration: 0)
		mixer.buses[1].setVolume(0.5, duration: 1)
		await Sleep(2)
		await smoothDisconnect()
	}

	func testFile() async {
		print("--- ", #function)
		let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "AudioNodesDemo/AudioNodesDemo/Resources/eyes-demo.m4a")
		let player = Player(url: url, sampleRate: systemFormat.sampleRate, isStereo: systemFormat.isStereo)!
		connect(player)
		await Sleep(5)
		await smoothDisconnect()
	}
}


@main
struct CLI {

	@AudioActor
	static func runTests() async {
		let system = System(isStereo: true)
		system.start()
//		await system.testSine()
//		await system.testMixer()
		await system.testFile()
	}


	static func main() async {
		await runTests()
	}
}
