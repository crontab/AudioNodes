//
//  main.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import AudioToolbox


// MARK: - System

class System: Node {

	private let unit: AudioUnit

	override init() {
		var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: Self.subtype(), componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
		let comp = AudioComponentFindNext(nil, &desc)!
		var tempUnit: AudioUnit?
		NotError(AudioComponentInstanceNew(comp, &tempUnit), 51000)
		unit = tempUnit!
	}

#if os(iOS)
	private class func subtype() -> UInt32 { kAudioUnitSubType_RemoteIO }
#else
	private class func subtype() -> UInt32 { kAudioUnitSubType_DefaultOutput }
#endif
}

@main
struct CLI {

	static func main() async throws {
		await Task { @AudioActor in
			let stereo = System()
			let buf = SafeAudioBufferList(isStereo: true, capacity: 512)
			_ = stereo._internalRender(frameCount: 512, buffers: buf.buffers)
			stereo.isEnabled = true
			print("Hello, World!")
		}.value
	}
}
