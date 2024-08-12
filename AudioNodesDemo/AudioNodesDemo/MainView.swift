//
//  MainView.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


struct MainView: View {
	@EnvironmentObject private var audio: AudioState


	var body: some View {
		VStack {
			top()
			Divider()

			Spacer()

			Divider()
			bottom()
		}
		.font(.text)
		.frame(maxWidth: .infinity)
		.padding(24)
		.tint(.orange)
		.background { Color.stdBackground.ignoresSafeArea() }
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

			Toggle(isOn: $audio.isRunning) {
				Text("System".uppercased())
					.foregroundColor(.gray)
			}
			.frame(width: 112)
		}
	}


	private func bottom() -> some View {
		VStack {
			HStack {
				Button {
					audio.isPlaying = !audio.isPlaying
				} label: {
					Group {
						if audio.isPlaying {
							Image(systemName: "square.fill")
						}
						else {
							Image(systemName: "triangle.fill")
								.rotationEffect(.degrees(90))
								.offset(x: 1)
						}
					}
					.font(.system(size: 18))
					.frame(width: 36, height: 36)
				}
				.buttonStyle(.bordered)
			}
		}
	}
}


#Preview {
	MainView()
		.environmentObject(AudioState())
}
