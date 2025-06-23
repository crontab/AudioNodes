//
//  FFTLevelsView.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 23.06.25.
//

import SwiftUI


private let barWidth = 3.0
private let spacing = 3.0


struct FFTLevelsView: View {

	let levels: [Float]
	let height: Double

	var body: some View {
		HStack(alignment: .bottom, spacing: 3) {
			ForEach(levels, id: \.self) { level in
				Bar()
					.stroke(.tint, style: .init(lineWidth: barWidth, lineCap: .round))
					.frame(width: barWidth, height: height * Double(level.clamped(to: 0...1)))
					.offset(x: barWidth / 2)
			}
		}
		.frame(height: height, alignment: .bottom)
	}


	private struct Bar: Shape {

		nonisolated func path(in rect: CGRect) -> Path {
			var path = Path()
			path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
			path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
			return path
		}
	}
}


private extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self { min(max(self, limits.lowerBound), limits.upperBound) }
}


#Preview {
	FFTLevelsView(levels: [0.2, 0.1, 0.5, 0.3, 0, 0.4, 0.25], height: 16)
		.tint(.orange)
		.background(.gray)
		.padding()
	Spacer()
}
