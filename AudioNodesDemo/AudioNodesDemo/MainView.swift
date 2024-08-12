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
		GeometryReader { geometry in
			VStack(spacing: 24) {
				top()
				Divider()

				Spacer()

				inOut(width: geometry.size.width)
				Divider()
				bottom()
			}
			.font(.text)
			.frame(maxWidth: .infinity)
			.padding(16)
			.tint(.orange)
			.background { Color.stdBackground.ignoresSafeArea() }
		}

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
				Text("Nodes".uppercased())
				Text(System.version ?? "")
					.font(.smallText)
					.foregroundColor(.secondary)
			}
			.font(.header)

			Spacer()

			toggle(isOn: $audio.isRunning, left: "System")
		}
	}


	private func inOut(width: Double) -> some View {
		HStack {
			SectionView {
				Text("OUTPUT")
					.font(.smallText)
			} content: {
				VStack(alignment: .trailing, spacing: 16) {
					toggle(isOn: $audio.isOutputEnabled, left: "On")
						.padding(.bottom, 8)
					ProgressView(value: audio.normalizedOutputGainLeft)
					ProgressView(value: audio.normalizedOutputGainRight)
				}
				.frame(width: min(120, width / 4))
				.padding(.vertical, 6)
			}

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
				Text(left)
					.foregroundColor(.secondary)
					.offset(y: 1)
			}
			Toggle(isOn: isOn) { }
				.labelsHidden()
			if let right {
				Text(right)
					.foregroundColor(.secondary)
					.offset(y: 1)
			}
		}
	}
}


#Preview {
	MainView()
		.environmentObject(AudioState())
}
