//
//  main.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 09.08.24.
//

import Foundation
import AudioToolbox


// MARK: - Driver

class Driver: Node {

	func connect(_ input: Node) { withAudioLock { _userConnector.connectSafe(input) } }

	func disconnect() { withAudioLock { _userConnector.disconnectSafe() } }


	// Internal

	override func _render(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		guard let input = _connector.input else {
			return FillSilence(frameCount: frameCount, buffers: buffers)
		}
		return input._internalRender(frameCount: frameCount, buffers: buffers)
	}


	override func _willRenderSafe() {
		super._willRenderSafe()
		_connector = _userConnector
	}


	override func willConnectSafe(with format: StreamFormat) {
		super.willConnectSafe(with: format)
		_userConnector.setFormatSafe(format)
	}


	override func didDisconnectSafe() {
		super.didDisconnectSafe()
		_userConnector.resetFormat()
	}


	// Private

	private var _userConnector = Connector()
	private var _connector = Connector()
}


// MARK: - System

class System: Driver {

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
