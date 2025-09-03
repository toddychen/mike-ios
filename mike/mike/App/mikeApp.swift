//
//  mikeApp.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import SwiftUI
import SwiftData

@main
struct mikeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Game.self,
            AudioSegment.self,
            TextBlock.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(sharedModelContainer)
    }
}
