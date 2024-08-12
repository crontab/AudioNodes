//
//  FontEx.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import SwiftUI


extension Font {

	static let avenir = "AvenirNextCondensed-Medium"
	static let avenirMedium = "AvenirNextCondensed-DemiBold"

	static let text = Font.custom(avenir, size: 17)
	static let smallText = Font.custom(avenir, size: 13)
	static let header = Font.custom(avenirMedium, size: 20)
}
