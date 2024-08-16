//
//  SectionView.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 12.08.24.
//

import SwiftUI


struct SectionView<Content: View, Title: View>: View {

	@ViewBuilder private let title: () -> Title
	@ViewBuilder private let content: () -> Content


	init(title: @escaping () -> Title = EmptyView.init, content: @escaping () -> Content) {
		self.title = title
		self.content = content
	}


	var body: some View {
		content()
			.padding(.vertical, 24)
			.padding(.horizontal, 16)
			.background {
				RoundedRectangle(cornerRadius: 12)
					.fill(.clear)
					.stroke(.white.opacity(0.2), lineWidth: 2)
					.padding(.vertical, 8)
					.mask {
						ZStack { // inverted mask trick
							Rectangle()
							titleBox(background: .primary)
								.blendMode(.destinationOut)
						}
					}
					.overlay {
						titleBox(background: .clear)
					}
			}
	}


	@ViewBuilder
	private func titleBox(background: Color) -> some View {
		title()
			.padding(.horizontal, 6)
			.background(background)
			.offset(x: 20)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}


#Preview {
	SectionView {
		Text("Output")
			.font(.caption)
	} content: {
		Text("Hello, world!")
	}
	.background(.tertiary)
}
