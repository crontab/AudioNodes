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
			[.yellow, .orange.opacity(0.4)] :
		[.gray.opacity(0.2), .gray.opacity(0.3)]
		ZStack {
			Circle()
				.fill(.stdBackground)
				.fill(RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: size / 1.5))
			Circle()
				.stroke(.black, lineWidth: 1)
				.shadow(color: .white.opacity(isOn ? 0.5 : 0.3), radius: shadow / 1.5, x: shadow, y: shadow)
				.shadow(color: .black.opacity(0.3), radius: shadow / 1.5, x: -shadow, y: -shadow)
		}
		.animation(.easeInOut(duration: 0.05), value: isOn)
		.frame(width: size, height: size)
		.clipShape(Circle())
		.shadow(radius: 3)
		.disabled(!enabled)
		.opacity(enabled ? 1 : 0.3)
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
			.background(.stdBackground)
		}
	}

	return Preview()
}
