//
//  CLITest.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import AVFoundation
import AudioToolbox

func resUrl(_ name: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "AudioNodesDemo/AudioNodesDemo/Resources/").appendingPathComponent(name) }


class PlayerProgress: PlayerDelegate {
	func player(_ player: Player, isAt time: TimeInterval) {
		guard abs(time - prevTime) >= 0.2 else { return }
		prevTime = time
		print("Player:", String(format: "%.2f", time))
	}

	func playerDidEndPlaying(_ player: Player) {
		print("Player:", "ended")
	}

	private var prevTime: TimeInterval = 0
}


@AudioActor
extension System {

	func testSine() async {
		print("--- ", #function)
		let sine = SineGenerator(freq: 440, isEnabled: true)
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
		let sine1 = SineGenerator(freq: 440, isEnabled: true)
		let sine2 = SineGenerator(freq: 480, isEnabled: true)
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
		let progress = PlayerProgress()
		let player = FilePlayer(url: resUrl("eyes-demo.m4a"), sampleRate: systemFormat.sampleRate, isStereo: systemFormat.isStereo, delegate: progress)!
		connect(player)
		player.isEnabled = true
		await Sleep(5)
		await smoothDisconnect()
	}


	func testQueuePlayer() async {
		print("--- ", #function)
		let progress = PlayerProgress()
		let player = QueuePlayer(sampleRate: systemFormat.sampleRate, isStereo: systemFormat.isStereo, delegate: progress)
		["deux.m4a", "trois.m4a"].forEach {
			precondition(player.addFile(url: resUrl($0)))
		}
		connect(player)
		player.isEnabled = true
		await Sleep(2)
		player.time = 0.15
		player.isEnabled = true
		_ = player.addFile(url: resUrl("eyes-demo.m4a"))
		await Sleep(3)
		await smoothDisconnect()
	}


	@AudioFileActor
	func testMemoryPlayer() async {
		print("--- ", #function)
		
		let data = AudioData(durationSeconds: 10, sampleRate: systemFormat.sampleRate, isStereo: systemFormat.isStereo)
		let file = AudioFileReader(url: resUrl("eyes-demo.m4a"), sampleRate: systemFormat.sampleRate, isStereo: systemFormat.isStereo)!
		let safeBuffer = SafeAudioBufferList(isStereo: systemFormat.isStereo, capacity: 8192)
		let buffers = safeBuffer.buffers
		let frameCount = buffers[0].sampleCount

		while true {
			var numRead: UInt32 = 0
			let status = file.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)
			if status != noErr || numRead == 0 {
				break
			}
			data.write(frameCount: Int(numRead), buffers: buffers, offset: 0)
		}

		let progress = PlayerProgress()
		let player = MemoryPlayer(data: data, isEnabled: true, delegate: progress)
		connect(player)

		await Sleep(10)
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
//		await system.testFile()
//		await system.testQueuePlayer()
		await system.testMemoryPlayer()
	}


	static func main() async {
		await runTests()
	}
}
