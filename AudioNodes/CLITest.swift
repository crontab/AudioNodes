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

	func testVolumeControl() async {
		print("--- ", #function)
		let sine = SineGenerator(freq: 440)
		let volume = VolumeControl()
		volume.connect(sine)
		connect(volume)
		await Sleep(1)
		volume.setVolume(0.5, duration: 1)
		await Sleep(1)
		volume.setVolume(1, duration: 0.5)
		await Sleep(0.5)
		await smoothDisconnect()
	}
}


@main
struct CLI {

	@AudioActor
	static func runTests() async {
		let system = System(isStereo: true)
		system.start()
		await system.testSine()
		await system.testVolumeControl()
	}


	static func main() async {
		await runTests()
	}
}
