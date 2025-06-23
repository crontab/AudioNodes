//
//  MainView.swift
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI
import AudioNodes


private let fileUrl = Bundle.main.url(forResource: "eyes-demo", withExtension: "m4a")!


struct MainView: View {
	@StateObject private var audio: MainAudioState = .init()

	@State private var showShare: URL?


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
		.padding(16)
		.tint(.orange)
		.background { Color.stdBackground.ignoresSafeArea() }

		.onAppear {
			guard !Globals.isPreview else { return }
			audio.isRunning = true
		}

		.sheet(item: $showShare) { item in
			ShareTempFileView(url: item)
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

			toggle(isOn: $audio.isRunning, left: "On")
		}
	}


	private func inOut() -> some View {
		HStack(alignment: .bottom) {
			outputSection()
				.frame(maxWidth: 152)
			Spacer()
			VStack {
				inputSection()
				voiceSection()
			}
			.frame(maxWidth: 152)
		}
	}


	private func voiceSection() -> some View {
		SectionView {
			VStack(alignment: .trailing) {
				toggle(isOn: $audio.isVoiceEnabled, left: "Voice mode", enabled: audio.isRunning && audio.isInputEnabled)
					.padding(.bottom, 8)
				ProgressView(value: 0)
			}
		}
	}


	private func outputSection() -> some View {
		SectionView {
			VStack(alignment: .trailing, spacing: 16) {
				toggle(isOn: $audio.isOutputEnabled, left: "Output", enabled: audio.isRunning)
					.padding(.bottom, 8)
				Group {
					ProgressView(value: audio.outputGainLeft)
					ProgressView(value: audio.outputGainRight)
				}
				.tint(.blue)
			}
		}
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
				HStack {
					saveButton()
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


	@State private var saving: Bool = false

	private func saveButton() -> some View {
		audioButton("Save") {
			saving = true
			Task {
				let url = Globals.tempFileURL(ext: "m4a")
				print("Saving file to: \(url)")
				if audio.saveRecording(to: url) {
					showShare = url
				}
				saving = false
			}
		} label: {
			Image(systemName: "square.and.arrow.down.fill")
		}
		.tint(.secondary)
		.disabled(audio.recorderPosition == 0 || saving)
	}


	private func recButton() -> some View {
		audioButton("Rec") {
			audio.isRecording = !audio.isRecording
		} label: {
			Image(systemName: "circle.fill")
		}
		.tint(audio.isRecording ? .red : .secondary)
		.disabled(!audio.isInputEnabled)
	}


	private func playButton() -> some View {
		audioButton("Play") {
			audio.isRecordingPlaying = !audio.isRecordingPlaying
		} label: {
			if audio.isRecordingPlaying {
				Image(systemName: "square.fill")
			}
			else {
				Image(systemName: "triangle.fill")
					.rotationEffect(.degrees(90))
					.offset(x: 0.5)
			}
		}
		.tint(audio.isRecordingPlaying ? .blue : .secondary)
		.disabled(!audio.isInputEnabled || audio.recorderPosition == 0)
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
