//
//  WaveformView.swift
//
//  Created by Hovik Melikyan on 20.08.24.
//

import SwiftUI


struct WaveformView: View {

	static let Padding = 30.0 // for scrollable only

	let waveform: Waveform
	let color: Color
	var scrollable: Bool = true

	var body: some View {
		GeometryReader { geometry in
			VStack {
				Spacer()
				LegacyScrollView(action: .constant(scrollable ? .idle : .disable)) {
					let barWidth = 2.0
					let barSpacing = 1.0
					let dbMin = -48.0
					let dbBand = -dbMin
					HStack(alignment: .bottom, spacing: barSpacing) {
						ForEach(waveform.series.indices, id: \.self) { index in
							let value = waveform.series[index]
							let h = (max(dbMin, min(0, Double(value))) - dbMin) / dbBand // 0...1
							RoundedRectangle(cornerRadius: 0.5)
								.fill(color)
								.frame(width: barWidth, height: h * (geometry.size.height - barWidth) + barWidth)
						}
					}
					.padding(.horizontal, scrollable ? Self.Padding : 0)
				}
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
		.clipped()
	}
}


#Preview {
	VStack {
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange)
			.frame(width: 100, height: 32)
		WaveformView(waveform: .fromHexString("d0e4efe8f0eaf1e7f0e9f0ecedeeebefeaf1e8f1eaf1e9efe8eee9edeeeceff1eff2f0f0f0f0f2ee"), color: .orange, scrollable: false)
			.frame(width: 100, height: 32)
			.scaleEffect(y: -1)
	}
}
