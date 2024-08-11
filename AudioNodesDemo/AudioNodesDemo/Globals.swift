//
//  Globals.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import Foundation


final class Globals {

	static let isPreview: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
