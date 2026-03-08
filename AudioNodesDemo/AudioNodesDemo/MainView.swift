//
//  MainView.swift
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI
import AudioNodes


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


struct MainView: View {
	@StateObject private var audio = MainAudioState()


	var body: some View {
		VStack(spacing: 0) {
			top()
				.padding(.bottom)
			Divider()

			Spacer()

			inOut()
			Divider()

			bottom()
				.padding(.vertical)
		}
		.font(.text)
		.frame(maxWidth: .infinity)
		.padding(16)
		.tint(.orange)
		.backgroundStyle(.background.secondary)

		.onAppear {
			guard !Globals.isPreview else { return }
			audio.isRunning = true
		}
	}


	private func top() -> some View {
		HStack(spacing: 12) {
			Image(.kokopelli).resizable().scaledToFit()
				.frame(height: 52)
			VStack(alignment: .leading) {
				Text("Audio Nodes".uppercased())
				Text(System.version ?? "")
					.font(.smallText)
					.foregroundColor(.secondary)
			}
			.font(.header)

			Spacer()

			toggle(isOn: $audio.isRunning, left: "On")
		}
	}


	private func inOut() -> some View {
		HStack(alignment: .bottom) {
			outputSection()
				.frame(maxWidth: 152)
			Spacer()
			inputSection()
				.frame(maxWidth: 152)
		}
	}


	private func outputSection() -> some View {
		SectionView {
			VStack(alignment: .trailing, spacing: 16) {
				toggle(isOn: $audio.isOutputEnabled, left: "Output", enabled: audio.isRunning)
					.padding(.bottom, 8)
				Group {
					let left = Double(audio.outputGainLeft), right = Double(audio.outputGainRight)
					levelView(value: left)
						.animation(.linear(duration: 0.1), value: left)
					if audio.isOutputStereo {
						levelView(value: right)
							.animation(.linear(duration: 0.1), value: right)
					}
				}
			}
		}
	}


	private func levelView(value: Double) -> some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				Capsule()
					.fill(.background.quaternary)
					.stroke(.background.tertiary)
				Capsule()
					.fill(.tint)
					.frame(width: proxy.size.width * max(0, min(1, value)))
			}
		}
		.frame(height: 8)
	}


	private func inputSection() -> some View {
		SectionView {
			VStack(spacing: 16) {
				HStack(alignment: .center) {
					Spacer()
					toggle(isOn: $audio.isInputEnabled, left: "Input", enabled: audio.isRunning)
				}
				HStack {
					recButton()
					Spacer()
					playButton()
				}
				let levels = audio.inputLevels.count > 7 ? audio.inputLevels[1...7] : audio.inputLevels[...]
				FFTLevelsView(levels: Array(levels), height: 16)
					.tint(.orange)
			}
		}
	}


	private func bottom() -> some View {
		VStack {
			// TODO: Wave form
			HStack {
				Button {
					audio.isFilePlaying.toggle()
				} label: {
					Image(systemName: audio.isFilePlaying ? "square.fill" : "play.fill")
						.font(.system(size: 18))
						.frame(width: 36, height: 36)
				}
				.buttonStyle(.bordered)
				.focusEffectDisabled()
			}
		}
	}


	@State private var saving: Bool = false


	private func recButton() -> some View {
		audioButton("Rec") {
			audio.isRecording.toggle()
		} label: {
			Image(systemName: audio.isRecording ? "square.fill" : "circle.fill")
		}
		.tint(audio.isRecording ? .red : .secondary)
		.disabled(!audio.isInputEnabled)
	}


	private func playButton() -> some View {
		audioButton("Play") {
			audio.isRecordingPlaying.toggle()
		} label: {
			Image(systemName: audio.isRecordingPlaying ? "square.fill" : "play.fill")
		}
		.tint(audio.isRecordingPlaying ? .blue : .secondary)
		.disabled(!audio.isInputEnabled || audio.isRecording)
	}


	private func audioButton<L: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
		Button(action: action) {
			VStack(spacing: 4) {
				label()
					.font(.system(size: 12))
				Text(title.uppercased())
					.font(.smallText)
			}
			.padding(.top, 2)
			.frame(width: 24)
		}
		.buttonStyle(.bordered)
		.focusEffectDisabled()
	}


	private func toggle(isOn: Binding<Bool>, left: String? = nil, right: String? = nil, enabled: Bool = true) -> some View {
		HStack(spacing: 8) {
			if let left {
				Text(left)
					.foregroundColor(.secondary)
					.offset(y: 1)
			}
			LEDToggle(isOn: isOn, enabled: enabled)
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
}
