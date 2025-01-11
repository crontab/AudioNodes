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

func tempRecUrl(_ name: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("..").appendingPathComponent(name) }


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


extension System {

	func testSine() async {
		print("---", #function)
		let sine = SineGenerator(freq: 440, format: outputFormat, isEnabled: true)
		connectSource(sine)
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
		enum Channel: Int, CaseIterable {
			case one, two
		}
		print("---", #function)
		let sine1 = SineGenerator(freq: 440, format: outputFormat, isEnabled: true)
		let sine2 = SineGenerator(freq: 480, format: outputFormat, isEnabled: true)
		let mixer = EnumMixer<Channel>(format: outputFormat)
		mixer[.one].connectSource(sine1)
		mixer[.two].connectSource(sine2)
		connectSource(mixer)
		await Sleep(1)
		mixer[.one].setVolume(0.5, duration: 1)
		await Sleep(1)
		mixer[.one].setVolume(1, duration: 0)
		mixer[.two].setVolume(0.5, duration: 1)
		await Sleep(2)
		await smoothDisconnect()
	}


	func testFile() async {
		print("---", #function)
		let progress = PlayerProgress()
		let player = FilePlayer(url: resUrl("eyes-demo.m4a"), format: outputFormat, delegate: progress)!
		connectSource(player)
		player.isEnabled = true
		await Sleep(5)
		await smoothDisconnect()
	}


	func testQueuePlayer() async {
		print("---", #function)
		let progress = PlayerProgress()
		let player = QueuePlayer(format: outputFormat, delegate: progress)
		["deux.m4a", "trois.m4a"].forEach {
			precondition(player.addFile(url: resUrl($0)))
		}
		connectSource(player)
		player.isEnabled = true
		await Sleep(2)
		player.time = 0.15
		player.isEnabled = true
		_ = player.addFile(url: resUrl("eyes-demo.m4a"))
		await Sleep(3)
		await smoothDisconnect()
	}


	func testMemoryPlayer() async {
		print("---", #function)

		let data = AudioData(durationSeconds: 2, format: outputFormat)
		let file = AudioFileReader(url: resUrl("eyes-demo.m4a"), format: outputFormat)!
		let safeBuffer = SafeAudioBufferList(isStereo: outputFormat.isStereo, capacity: 8192)
		let buffers = safeBuffer.buffers
		let frameCount = buffers[0].sampleCount

		while true {
			var numRead = 0
			let status = file.readSync(frameCount: frameCount, buffers: buffers, numRead: &numRead)
			if status != noErr || numRead == 0 {
				break
			}
			let result = data.write(frameCount: Int(numRead), buffers: buffers)
			if result < numRead {
				break
			}
		}

		let progress = PlayerProgress()
		let player = MemoryPlayer(data: data, delegate: progress)
		connectSource(player)

		let waveform = await Task.detached {
			Waveform.fromSource(data, ticksPerSec: 4)
		}.value

		player.reset()
		player.isEnabled = true
		await Sleep(3)
		await smoothDisconnect()

		if let waveform {
			let s = waveform.toHexString()
			print(s)
			let w = Waveform.fromHexString(s)
			assert(w.ticks == waveform.ticks)
		}
	}


	func testNR() async {
		print("---", #function)
		let url = tempRecUrl("ios.m4a")
		guard let original = AudioData(url: url, format: monoInputFormat) else {
			print("ERROR: couldn't load file", url.path(percentEncoded: false))
			return
		}

		let progress = PlayerProgress()

//		do {
//			print("--- playing original")
//			let player = MemoryPlayer(data: original, delegate: progress)
//			connectSource(player)
//			player.isEnabled = true
//			await Sleep(player.duration)
//			await smoothDisconnect()
//		}

		// Process
		let processed = AudioData(durationSeconds: original.capacity, format: original.format)
		do {
			print("--- processing")
			original.resetRead()
			let processor = OfflineProcessor(source: original, sink: processed)
			let noiseGate = NoiseGate(format: original.format)
			noiseGate.connectSource(processor)
			let result = processor.run(entry: noiseGate)
			if result != noErr {
				processed.clear()
			}
		}

		// Play processed
		do {
			print("--- playing processed")
			let player = MemoryPlayer(data: processed, delegate: progress)
			connectSource(player)
			player.isEnabled = true
			await Sleep(player.duration)
			await smoothDisconnect()
		}
	}


	func testSyncPlayer() async throws {
		print("---", #function)
		let url = tempRecUrl("ios.m4a")
		try await FilePlayer.playAsync(url, format: outputFormat, driver: self)
	}


	func levelAnalysis() async throws {
		for name in ["ios", "ios2", "ios3", "mac"] {
			guard let file = AudioFileReader(url: tempRecUrl(name + ".m4a"), format: outputFormat) else {
				return
			}
			let data = AudioData(durationSeconds: Int(ceil(file.estimatedDuration)), format: file.format)
			_ = adjustVoiceRecording(source: file, sink: data, nr: true, diagName: name)
			data.resetRead()
			try await MemoryPlayer.playAsync(data, driver: self)
		}
	}
}


func rmsTests() {

	// Result: for every 0.1 volume the RMS changes by 4dB

	func testVol(_ volume: Float) {
		let fmt: StreamFormat = .defaultMono
		let sine = SineGenerator(freq: 440, volume: volume, format: fmt)
		let data = AudioData(durationSeconds: 1, format: fmt)
		_ = OfflineProcessor(source: sine, sink: data)
			.run()
		let waveform = Waveform.fromSource(data, ticksPerSec: 4)
		print("Vol=\(volume), level=\(waveform?.ticks.max() ?? 0)")
	}

	for i in 0..<10 {
		testVol(1 - Float(i) / 10)
	}
}


func adjustVoiceRecording(source: StaticDataSource, sink: StaticDataSink, nr: Bool, diagName: String) -> Waveform? {

	let format = source.format

	// Calculate the min and max dB levels within 1/48 chunks
	source.resetRead()
	guard let waveform = Waveform.fromSource(source, ticksPerSec: 48) else {
		return nil
	}
	guard let range = waveform.range else {
		return nil
	}

	// See how much gain should be applied based on how far the quitest part is from the NR level of 40dB (minus 10dB = -50dB) and the loudest part is from our standard -12dB level.
	// Before running NR we will apply gain that is the minimum of the two:
	let upperGain = (STD_NORMAL_PEAK - range.upperBound)
//		.clamped(to: -12...24)
	let lowerGain: Float = 0 // (STD_NOISE_GATE - 10 - range.lowerBound)
//		.clamped(to: 0...12)

	DLOG("\(diagName): range = \(range), delta.lo = \(lowerGain), hi = \(upperGain)")

	// 1. Pre-NR gain adjustment
	// We divide the gain by 40 because each 4dB gain roughly translates to 0.1 volume:
	let preNRGain = nr ? min(upperGain, lowerGain) : 0
	let preNRNode = VolumeControl(format: format, initialVolume: 1 /*+ preNRGain / 40*/)

	// 2. Optional NR
	let nrNode = NoiseGate(format: format, thresholdDb: STD_NOISE_GATE)
	nrNode.isBypassing = !nr

	// 3. Post-NR gain adjustment
	let postNRGain = upperGain - preNRGain
	let postNRNode = VolumeControl(format: format, initialVolume: 1 + postNRGain / 40)

	// 4. Create a processor and connect the chain
	let processor = OfflineProcessor(source: source, sink: sink, divisor: 25)
	postNRNode
		.connectSource(nrNode)
		.connectSource(preNRNode)
		.connectSource(processor)

	// 5. Run the processing chain
	source.resetRead()
	let result = processor.run(entry: postNRNode)
	if result != noErr {
		return nil
	}

	return waveform
}


@main
struct CLI {

	static func runTests() async throws {
		let system = Stereo()
		system.start()
//		await system.testSine()
//		await system.testMixer()
//		await system.testFile()
//		await system.testQueuePlayer()
//		await system.testMemoryPlayer()
//		await system.testNR()
//		rmsTests()
//		try await system.testSyncPlayer()
		try await system.levelAnalysis()
	}


	static func main() async {
		do {
			try await runTests()
		}
		catch {
			DLOG("\(error)")
		}
	}
}
