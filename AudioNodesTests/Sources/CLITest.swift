//
//  CLITest.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import AVFoundation


func resUrl(_ name: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "AudioNodesDemo/AudioNodesDemo/Resources/").appendingPathComponent(name) }

func tempRecUrl(_ name: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("..").appendingPathComponent(name) }


class PlayerProgress: PlayerDelegate {
	func player(_ player: Player, isAt time: TimeInterval) {
		guard abs(time - prevTime) >= 0.2 else { return }
		prevTime = time
		print("Player:", String(format: "%.2f", time))
	}

	func playerDidEndPlaying(_ player: Player) {
		print("Player:", "ended", String(format: "%.2f", player.time))
	}

	private var prevTime: TimeInterval = 0
}


class FFTDelegate: FFTMeterDelegate {
	func fftMeterDidUpdateLevels(_ fftMeter: FFTMeter, levels: [Float]) {
		print(levels.map { String(format: "%.1f", $0) })
	}
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
		let mem = MemoryPlayer(data: AudioData(url: resUrl("deux.m4a"), format: outputFormat)!)
		player.addPlayer(mem)
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

		let data = AudioData(durationSeconds: 5, format: outputFormat)
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
		player.duration = 2.5
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


	func testNR() async throws {
		print("---", #function)
		let url = tempRecUrl("ios.m4a")
		guard let original = AudioData(url: url, format: inputFormat) else {
			print("ERROR: couldn't load file", url.path(percentEncoded: false))
			throw AudioError.fileOpen
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
			try NoiseGate(format: original.format)
				.runOffline(source: original, sink: processed)
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
			let url = tempRecUrl(name + ".m4a")
			guard let file = AudioData(url: url, format: outputFormat) else {
				print("ERROR: couldn't load file", url.path(percentEncoded: false))
				throw AudioError.fileOpen
			}
			let data = AudioData(durationSeconds: Int(ceil(file.estimatedDuration)), format: file.format)
			_ = try adjustVoiceRecording(source: file, sink: data, diagName: name)
			data.resetRead()
			try await MemoryPlayer.playAsync(data, driver: self)
		}
	}


	func eqTest() async throws {
		let name = "ios"
		let url = tempRecUrl(name + ".m4a")
		guard let origData = AudioData(url: url, format: outputFormat) else {
			print("ERROR: couldn't load file", url.path(percentEncoded: false))
			throw AudioError.fileOpen
		}
		try await MemoryPlayer.playAsync(origData, driver: self)

		origData.resetRead()
		let eq = EQFilter(format: outputFormat, params: EQParameters(type: .highPass, freq: 3000, bw: 1))
		let sink = AudioData(durationSeconds: Int(ceil(origData.estimatedDuration)), format: origData.format)
		try eq.runOffline(source: origData, sink: sink)

		sink.resetRead()
		try await MemoryPlayer.playAsync(sink, driver: self)
	}


	func eqTest2() async throws {
		print("---", #function)
		let url = tempRecUrl("456" + ".m4a") // resUrl("eyes-demo.m4a")
		guard let player = FilePlayer(url: url, format: outputFormat) else {
			throw AudioError.fileOpen
		}
		let eq = MultiEQFilter(format: outputFormat, params: [
			.init(type: .highPass, freq: 135, bw: 2.5),
			.init(type: .lowPass, freq: 7000, bw: 3),
			.init(type: .peaking, freq: 830, bw: 1, gain: -12),
//			.init(type: .peaking, freq: 2450, bw: 1, gain: 2),
		], isEnabled: true)
		eq.connectSource(player)
		connectSource(eq)
		player.isEnabled = true
		await Sleep(3)
		player.time = 0
		player.isEnabled = true
		print("---", #function, "bypassing")
		eq.isBypassing = true
		await Sleep(3)
		await smoothDisconnect()
	}


	func rmsTests() async throws {

		// Result: for every 0.1 volume the RMS changes by 4dB

		func testVol(_ volume: Float) async throws {
			let fmt: StreamFormat = .defaultMono
			let sine = SineGenerator(freq: 440, format: fmt)
			let sink = AudioData(durationSeconds: 1, format: fmt)
			try VolumeControl(format: fmt, initialVolume: volume)
				.runOffline(source: sine, sink: sink)
//			sink.resetRead()
//			try await MemoryPlayer.playAsync(sink, driver: self)
			let waveform = Waveform.fromSource(sink, ticksPerSec: 4)
			print("Vol=\(volume), level=\(waveform?.ticks.max() ?? 0)")
		}

		for i in 0..<10 {
			try await testVol(1 - Float(i) / 10)
		}
	}


	func fftTest() async throws {
		let player = FilePlayer(url: resUrl("eyes-demo.m4a"), format: outputFormat)!
		connectSource(player)

		let delegate = FFTDelegate()
		player.connectMonitor(FFTMeter(format: player.format, delegate: delegate))

		player.isEnabled = true
		await Sleep(2)
		player.isEnabled = false
		await smoothDisconnect()
	}
}


func adjustVoiceRecordingNR(source: StaticDataSource, sink: StaticDataSink, nr: Bool, diagName: String) throws -> Waveform? {

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
	postNRNode
		.connectSource(nrNode)
		.connectSource(preNRNode)

	// 5. Run the processing chain
	source.resetRead()
	try postNRNode.runOffline(source: source, sink: sink)

	return waveform
}


func adjustVoiceRecording(source: StaticDataSource, sink: StaticDataSink, diagName: String) throws -> Waveform? {

	let format = source.format

	// Calculate the min and max dB levels within 1/48 chunks
	source.resetRead()
	guard let waveform = Waveform.fromSource(source, ticksPerSec: 48) else {
		return nil
	}
	guard let range = waveform.range else {
		return nil
	}

	// See how much gain should be applied based on how far the loudest part is from our standard -12dB level
	let deltaGain = (STD_NORMAL_PEAK - range.upperBound)
		.clamped(to: -12...24)

	DLOG("\(diagName): range = \(range), delta = \(deltaGain)")

	// Gain adjustment:
	// We divide the gain by 40 because each 4dB gain roughly translates to 0.1 volume:
	source.resetRead()
	try VolumeControl(format: format, initialVolume: 1 + deltaGain / 40)
		.runOffline(source: source, sink: sink)

	return waveform
}


@main
struct CLI {

	static func runTests() async throws {
		// Should be /Users/hovik/Projects/Other/AudioNodes
		print("cwd", FileManager.default.currentDirectoryPath)

		let system = Stereo()
		system.start()
//		await system.testSine()
//		await system.testMixer()
//		await system.testFile()
//		await system.testQueuePlayer()
//		await system.testMemoryPlayer()
//		try await system.testNR()
//		try await system.rmsTests()
//		try await system.testSyncPlayer()
//		try await system.levelAnalysis()
//		try await system.eqTest()
		try await system.eqTest2()
//		try await system.fftTest()

		await Sleep(0.1) // before disconnecting, to avoid clicks
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
