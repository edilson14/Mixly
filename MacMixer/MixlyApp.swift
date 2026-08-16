//
//  MixlyApp.swift
//  Mixly
//
//  Created by edilson14 on 23/07/26.
//

import SwiftUI

@main
struct MixlyApp: App {
    init() {
        _ = AudioKitController.shared
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(AudioKitController.shared)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)
    }
}
