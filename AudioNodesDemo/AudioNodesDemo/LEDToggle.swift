//
//  LEDToggle.swift
//
//  Created by Hovik Melikyan on 16.08.24.
//

import SwiftUI


struct LEDToggle: View {
	@Binding var isOn: Bool
	var enabled: Bool = true

	var body: some View {
		let isOn = isOn && enabled
		let colors: [Color] = isOn ?
			[.yellow, .orange] :
			[.gray.opacity(0.2), .gray.opacity(0.5)]
		ZStack {
			Circle()
				.fill(.background.secondary)
				.fill(RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: size / 1.5))
			Circle()
				.stroke(.quaternary, lineWidth: enabled ? 0.5 : 0)
				.shadow(color: .white.opacity(isOn ? 1 : 0.3), radius: shadow / 1.5, x: shadow, y: shadow)
				.shadow(color: .black.opacity(0.3), radius: shadow / 1.5, x: -shadow, y: -shadow)
		}
		.animation(.easeInOut(duration: 0.05), value: isOn)
		.frame(width: size, height: size)
		.shadow(color: .gray.opacity(0.5), radius: 3, x: 1, y: 1)
		.disabled(!enabled)
		.onTapGesture {
			if enabled {
				self.isOn.toggle()
			}
		}
	}

	private let size = 32.0 // should be static but oh well
	private let shadow = 1.0
}


#Preview {

	struct Preview: View {
		@State var one: Bool = true
		@State var two: Bool = false
		@State var three: Bool = true

		var body: some View {
			VStack {
				LEDToggle(isOn: $one)
				LEDToggle(isOn: $two)
				LEDToggle(isOn: $three, enabled: false)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(.background.secondary)
		}
	}

	return Preview()
}
