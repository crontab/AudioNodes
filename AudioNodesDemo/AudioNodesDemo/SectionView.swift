//
//  SectionView.swift
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
					.inset(by: 0.5)
					.fill(.clear)
					.stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
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
			.offset(x: 20, y: 0.5)
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
	.frame(maxWidth: .infinity, maxHeight: .infinity)
}
