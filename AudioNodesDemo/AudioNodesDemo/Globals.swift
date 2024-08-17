//
//  Globals.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


final class Globals {

	static let isPreview: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

	static func tempFileURL(ext: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(.nonce(length: 8)).appendingPathExtension(ext) }
}


extension URL: Identifiable {
	public var id: String { absoluteString }
}


extension String {

	private static let nonceChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

	static func nonce(length: Int = 20) -> Self {
		String((0..<length).map{ _ in Self.nonceChars.randomElement()! })
	}
}
