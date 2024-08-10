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
		let sine = SineGenerator(freq: 440)
		connect(sine)
		await Sleep(1)
		disconnect()
	}
}


@main
struct CLI {

	@AudioActor
	static func runTests() async {
		let system = System(isStereo: true)
		system.start()
		await system.testSine()
	}


	static func main() async {
		await runTests()
	}
}
