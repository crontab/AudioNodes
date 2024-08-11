//
//  MainView.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI


struct MainView: View {
	@EnvironmentObject private var system: System

	@State private var systemOn: Bool = false

	private let root: Node


	init() {
		root = SineGenerator(freq: 440)
	}


	var body: some View {
		VStack {
			top()
			Divider()
			Spacer()
		}
		.font(.text)
		.frame(maxWidth: .infinity)
		.padding(24)
		.tint(.orange)
		.background { Color.stdBackground.ignoresSafeArea() }

		.onAppear {
			systemOn = system.isRunning
		}

		.onChange(of: systemOn) { oldValue, newValue in
			guard !Globals.isPreview else { return }
			if newValue {
				Task {
					system.start()
					system.connect(root)
				}
			}
			else {
				Task {
					await system.smoothDisconnect()
					system.stop()
				}
			}
		}
	}


	private func top() -> some View {
		HStack(spacing: 16) {
			Image(.kokopelli)
			VStack(alignment: .leading) {
				Text("Audio".uppercased())
				Text("Nodes".uppercased()) //.foregroundColor(.gray)
				Text("1.0").font(.smallText).foregroundColor(.gray)
			}
			.font(.header)

			Spacer()

			Toggle(isOn: $systemOn) {
				Text("System".uppercased())
					.foregroundColor(.gray)
			}
			.frame(width: 112)
		}
	}
}


#Preview {
	MainView()
		.environmentObject(System(isStereo: true))
}
