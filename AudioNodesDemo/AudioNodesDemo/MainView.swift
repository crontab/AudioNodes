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
		VStack(spacing: 24) {
			top()
			Divider()

			Spacer()

			inOut()
			Divider()
			bottom()
		}
		.font(.text)
		.frame(maxWidth: .infinity)
		.padding(24)
		.tint(.orange)
		.background { Color.stdBackground.ignoresSafeArea() }

		.onAppear {
			guard !Globals.isPreview else { return }
			audio.isRunning = true
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

			toggle(isOn: $audio.isRunning, left: "System")
		}
	}


	private func inOut() -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 16) {
				toggle(isOn: $audio.isOutputEnabled, right: "Output")
				ProgressView(value: audio.normalizedOutputGainLeft)
				ProgressView(value: audio.normalizedOutputGainRight)
			}
			.frame(width: 120)

			Spacer()
		}
	}


	private func bottom() -> some View {
		VStack {
			// TODO: Wave form
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

			Text(String(format: "%.3fs", audio.playerTimePosition))
				.font(.smallText)
		}
	}


	func toggle(isOn: Binding<Bool>, left: String? = nil, right: String? = nil) -> some View {
		HStack(spacing: 8) {
			if let left {
				Text(left.uppercased())
					.foregroundColor(.gray)
					.offset(y: 1)
			}
			Toggle(isOn: isOn) { }
				.labelsHidden()
			if let right {
				Text(right.uppercased())
					.foregroundColor(.gray)
					.offset(y: 1)
			}
		}
	}
}


#Preview {
	MainView()
		.environmentObject(AudioState())
}
