//
//  MainView.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI


struct MainView: View {

	@State private var systemOn: Bool = false


	var body: some View {
		VStack {
			HStack {
				Image(.kokopelli)
				Group {
					Text("Audio".uppercased()) + Text("Nodes".uppercased()).foregroundColor(.gray) + Text(" 1.0")
				}
				.font(.header)

				Spacer()

				Toggle(isOn: $systemOn) {
					Text("System".uppercased())
				}
				.frame(width: 112)
			}
			Spacer()
			Text("Hello, world!")
		}
		.font(.text)
		.frame(maxWidth: .infinity)
		.padding()

		.onAppear {
		}
	}
}


#Preview {
	MainView()
}
