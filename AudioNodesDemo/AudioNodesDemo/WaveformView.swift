//
//  WaveformView.swift
//
//  Created by Hovik Melikyan on 20.08.24.
//

import SwiftUI


struct WaveformView: View {

	static let Padding = 30.0 // for scrollable only
	static let BarWidth = 2.0
	static let BarSpacing = 1.0

	let waveform: Waveform
	let color: Color
	var scrollable: Bool = true

	var body: some View {
		GeometryReader { geometry in
			LegacyScrollView(action: .constant(scrollable ? .idle : .disable)) {
				ZStack(alignment: .bottom) {
					Rectangle()
						.fill(.clear)
					HStack(alignment: .bottom, spacing: Self.BarSpacing) {
						let dbMin = -48.0
						let dbBand = -dbMin
						ForEach(waveform.ticks.indices, id: \.self) { index in
							let value = waveform.ticks[index]
							let h = (max(dbMin, min(0, Double(value))) - dbMin) / dbBand
							RoundedRectangle(cornerRadius: 0.5)
								.fill(color)
								.frame(width: Self.BarWidth, height: max(Self.BarWidth, h * (geometry.size.height)))
						}
					}
					.padding(.horizontal, scrollable ? Self.Padding : 0)
				}
				.frame(height: geometry.size.height)
			}

			.mask {
				if scrollable {
					HStack(spacing: 0) {
						Rectangle()
							.fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing))
							.frame(width: Self.Padding)
						Rectangle()
							.fill(.black)
						Rectangle()
							.fill(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing))
							.frame(width: Self.Padding)
					}
				}
				else {
					Rectangle()
				}
			}
		}
	}
}


#Preview {
	VStack(spacing: 0) {
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange, scrollable: false)
			.padding(.horizontal, WaveformView.Padding)
			.frame(width: 270, height: 40)
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange.opacity(0.6))
			.frame(width: 270, height: 20)
			.scaleEffect(y: -1)
	}
}
