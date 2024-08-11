//
//  AudioNodesDemoApp.swift
//  AudioNodesDemo
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI


@main
struct AudioNodesDemoApp: App {

	@StateObject private var system: System = .init(isStereo: true)


	var body: some Scene {
		WindowGroup {
			MainView()
				.environmentObject(system)
		}
	}
}


extension System: ObservableObject {
}
