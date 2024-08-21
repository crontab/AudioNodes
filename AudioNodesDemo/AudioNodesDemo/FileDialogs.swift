//
//  FileDialogs.swift
//
//  Created by Hovik Melikyan on 17.08.24.
//

import SwiftUI


struct ShareTempFileView: UIViewControllerRepresentable {

	let url: URL

	func makeUIViewController(context: Context) -> UIActivityViewController {
		let activity = UIActivityViewController(activityItems: [url], applicationActivities: [])
		activity.excludedActivityTypes = [.print, .addToReadingList]
		activity.completionWithItemsHandler = { type, success, _, error in
			try! FileManager.default.removeItem(at: url)
		}
		return activity
	}

	func updateUIViewController(_ vc: UIActivityViewController, context: Context) {
	}
}
