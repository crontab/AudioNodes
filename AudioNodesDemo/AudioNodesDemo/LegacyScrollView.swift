//
//  LegacyScrollView.swift
//
//  Created by Hovik Melikyan on 21.08.24.
//

import SwiftUI


// iOS 17 still can't report scroller position, hence our wrapper

struct LegacyScrollView<Content: View>: UIViewRepresentable {
	typealias OnScrollAction = (_ offset: Double, _ dragging: Bool) -> Void

	enum Action {
		case disable
		case idle
		case offset(_ offset: Double, animated: Bool)
	}

	private let axis: Axis = .horizontal
	@Binding private var action: Action
	private let content: () -> Content
	private var onScrollAction: OnScrollAction?


	init(action: Binding<Action> = .constant(.idle), @ViewBuilder content: @escaping () -> Content) {
		self._action = action
		self.content = content
	}


	func onScroll(_ action: @escaping OnScrollAction) -> Self {
		var view = self
		view.onScrollAction = action
		return view
	}


	func makeUIView(context: Context) -> HostedScrollView {
		let host = UIHostingController(rootView: content())
		host.view.backgroundColor = .clear

		let scrollView = HostedScrollView(host: host)
		scrollView.showsVerticalScrollIndicator = false
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.alwaysBounceVertical = axis == .vertical
		scrollView.alwaysBounceHorizontal = axis == .horizontal
		scrollView.delegate = context.coordinator

		scrollView.addSubview(host.view)

		return scrollView
	}


	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}


	func updateUIView(_ scrollView: HostedScrollView, context: Context) {
		scrollView.updateView(content: content)
		switch action {
			case .disable:
				scrollView.isScrollEnabled = false

			case .idle:
				scrollView.isScrollEnabled = true

			case .offset(let offset, let animated):
				scrollView.isScrollEnabled = true
				scrollView.setContentOffset(CGPoint(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0), animated: animated)
				Task {
					action = .idle
				}
		}
	}


	final class Coordinator: NSObject, UIScrollViewDelegate {
		let parent: LegacyScrollView

		init(_ parent: LegacyScrollView) {
			self.parent = parent
		}

		func scrollViewDidScroll(_ scrollView: UIScrollView) {
			let size = parent.axis == .horizontal ? scrollView.bounds.width : scrollView.bounds.height
			if size > 0, scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
				// Triggered only if interactive
				parent.onScrollAction?(offset(scrollView), true)
			}
		}

		func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
			parent.onScrollAction?(offset(scrollView), false)
		}

		func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
			if !decelerate {
				parent.onScrollAction?(offset(scrollView), false)
			}
		}

		private func offset(_ scrollView: UIScrollView) -> Double { parent.axis == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y }
	}


	final class HostedScrollView: UIScrollView {
		private let host: UIHostingController<Content>

		init(host: UIHostingController<Content>) {
			self.host = host
			super.init(frame: .zero)
		}

		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		fileprivate func updateView(content: () -> Content) {
			host.rootView = content()
			host.view.sizeToFit()
			contentSize = host.view.bounds.size
		}
	}
}


#Preview {
	LegacyScrollView(action: .constant(.idle)) {
		let colors = (0..<30).map { _ in Color(red: .random(in: 0.2...1), green:  .random(in: 0.2...1), blue:  .random(in: 0.2...1)) }
		HStack(spacing: 0) {
			ForEach(colors.indices, id: \.self) { index in
				let color = colors[index]
				Rectangle()
					.fill(color)
					.frame(width: 20, height: 100)
			}
		}
	}
	.onScroll { offset, didEnd in
		print(offset, didEnd)
	}
	.background(.tertiary)
}
