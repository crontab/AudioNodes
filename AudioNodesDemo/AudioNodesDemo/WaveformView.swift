//
//  WaveformView.swift
//
//  Created by Hovik Melikyan on 20.08.24.
//

import SwiftUI
import AudioNodes

let WaveformPadding = 30.0 // gradient area, for scrollable only
let WaveformBarWidth = 2.0
let WaveformBarSpacing = 2.0


struct WaveformView: View {
	typealias OnScrollAction = (_ offset: Double, _ idle: Bool) -> Void

	init(waveform: Waveform, color: Color, scrollable: Bool = true) {
		self.waveform = waveform
		self.color = color
		self.scrollable = scrollable
	}


	private let waveform: Waveform
	private let color: Color
	private let scrollable: Bool
	private var onScrollAction: OnScrollAction?

	var body: some View {
		GeometryReader { geometry in
			ScrollView(.horizontal, showsIndicators: false) {
				ZStack(alignment: .bottom) {
					Rectangle()
						.fill(.clear)
					HStack(alignment: .bottom, spacing: WaveformBarSpacing) {
						let dbMin = -48.0
						let dbBand = -dbMin
						ForEach(waveform.ticks.indices, id: \.self) { index in
							let value = waveform.ticks[index]
							let h = (max(dbMin, min(0, Double(value))) - dbMin) / dbBand
							let radius = WaveformBarWidth / 2
							UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
								.fill(color)
								.frame(width: WaveformBarWidth, height: max(WaveformBarWidth, h * (geometry.size.height)))
						}
					}
					.padding(.horizontal, scrollable ? WaveformPadding : 0)
				}
				.frame(height: geometry.size.height)
			}
			.scrollDisabled(!scrollable)
			.onScrollPhaseChange { old, new, context in
				switch new {
					case .idle:
						onScrollAction?(context.geometry.contentOffset.x, true)
					case .tracking, .interacting, .decelerating, .animating:
						onScrollAction?(context.geometry.contentOffset.x, false)
				}
			}

			.mask {
				if scrollable {
					HStack(spacing: 0) {
						Rectangle()
							.fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing))
							.frame(width: WaveformPadding)
						Rectangle()
							.fill(.black)
						Rectangle()
							.fill(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing))
							.frame(width: WaveformPadding)
					}
				}
				else {
					Rectangle()
				}
			}
		}
	}

	func onScroll(_ action: @escaping OnScrollAction) -> Self {
		var view = self
		view.onScrollAction = action
		return view
	}
}


#Preview {
	VStack(spacing: 0) {
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange, scrollable: false)
			.padding(.horizontal, WaveformPadding)
			.frame(width: 170, height: 40)
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange.opacity(0.6))
			.onScroll { offset, dragging in
				print(offset, dragging)
			}
			.frame(width: 170, height: 20)
			.scaleEffect(y: -1)
	}
}
