//
//  LEDToggle.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 16.08.24.
//

import SwiftUI


struct LEDToggle: View {
	@Binding var isOn: Bool

	var body: some View {
		let colors: [Color] = isOn ?
			[.yellow, .orange.opacity(0.6)] :
		[.gray.opacity(0.5), .gray.opacity(0.2)]
		ZStack {
			Circle()
				.fill(.stdBackground)
				.fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.43, y: 0.38), startRadius: 0, endRadius: size / 2))
			Circle()
				.stroke(.black, lineWidth: 1)
				.shadow(color: .white.opacity(0.5), radius: shadow / 1.5, x: shadow, y: shadow)
				.shadow(color: .black.opacity(0.3), radius: shadow / 1.5, x: -shadow, y: -shadow)
		}
		.animation(.easeInOut(duration: 0.05), value: isOn)
		.frame(width: size, height: size)
		.clipShape(Circle())
		.onTapGesture {
			isOn.toggle()
		}
	}

	private let size = 32.0 // should be static but oh well
	private let shadow = 1.0
}


#Preview {

	struct Preview: View {
		@State var one: Bool = true
		@State var two: Bool = false

		var body: some View {
			VStack {
				LEDToggle(isOn: $one)
				LEDToggle(isOn: $two)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(.blue)
		}
	}

	return Preview()
}
