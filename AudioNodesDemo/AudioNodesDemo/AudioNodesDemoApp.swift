//
//  AudioNodesDemoApp.swift
//
//  Created by Hovik Melikyan on 11.08.24.
//

import SwiftUI


@main
struct AudioNodesDemoApp: App {

	@StateObject private var audio: AudioState = .init()


	var body: some Scene {
		WindowGroup {
			MainView()
				.environmentObject(audio)
		}
	}
}
