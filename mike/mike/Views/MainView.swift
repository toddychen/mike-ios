//
//  MainView.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var games: [Game]
    
    // Hardcoded games for now
    private let hardcodedGames = [
        Game(gameId: "nfl.g.20250823025", name: "PreSeason: LA Chargers vs 49ers", date: Date(), isActive: true),
        Game(gameId: "nfl.g.20250904021", name: "Week 1: Cowboys vs Eagles", date: Date().addingTimeInterval(86400), isActive: false)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Mike")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Select a game to start recording")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                
                // Games list
                if games.isEmpty {
                    // Show hardcoded games if no games in database
                    VStack(spacing: 16) {
                        ForEach(hardcodedGames, id: \.gameId) { game in
                            GameRowView(game: game)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(games, id: \.gameId) { game in
                                GameRowView(game: game)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            setupInitialGames()
        }
    }
    
    private func setupInitialGames() {
        // Add hardcoded games to database if they don't exist
        for hardcodedGame in hardcodedGames {
            let existingGame = games.first { $0.gameId == hardcodedGame.gameId }
            if existingGame == nil {
                modelContext.insert(hardcodedGame)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save initial games: \(error)")
        }
    }
}

struct GameRowView: View {
    let game: Game
    
    var body: some View {
        NavigationLink(destination: RecordingView(game: game)) {
            VStack(spacing: 12) {
                // Top row: Game icon and status
                HStack(spacing: 16) {
                    // Football icon
                    VStack {
                        Image(systemName: "football.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .frame(width: 50, height: 50)
                    .background(game.isActive ? Color.green : Color.blue)
                    .cornerRadius(12)
                    
                    // Game ID
                    Text(game.gameId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                    
                    Spacer()
                    
                    // Status indicator
                    if game.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 8, height: 8)
                            Text("Inactive")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Bottom row: Game name (full width)
                HStack {
                    Text(game.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MainView()
        .modelContainer(for: [Game.self, AudioSegment.self, TextBlock.self], inMemory: true)
}
