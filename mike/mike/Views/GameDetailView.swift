//
//  GameDetailView.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import SwiftUI
import SwiftData

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @StateObject private var gamePlayAPI = GamePlayAPI()
    @StateObject private var ttsService = TextToSpeechService()
    @State private var isConvoEnabled = false
    @State private var secondsPerPlay = 20
    @State private var startTime = Date()
    @State private var gamePlays: [GamePlayResponse] = []
    @State private var replayInfo: ReplayInfo?
    @State private var showingError = false
    @State private var isRefreshPressed = false
    @State private var hasSpokenFirstPlay = false
    @State private var readConvoResponse = false // false = read details, true = read convoResponse
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                gameHeaderSection
                controlsSection
                actionButtonsSection
                if replayInfo != nil {
                    gameStatusSection
                }
                gamePlaysSection
            }
            .padding()
        }
        .navigationTitle("Game Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchGamePlays()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(gamePlayAPI.lastError ?? "Unknown error occurred")
        }
    }
    
    private var gameHeaderSection: some View {
        VStack(spacing: 16) {
            // Game icon, game ID and status
            HStack(spacing: 12) {
                VStack {
                    Image(systemName: "football.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .frame(width: 20, height: 20)
                .background(game.isActive ? Color.green : Color.blue)
                .cornerRadius(6)
                
                Text(game.gameId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
                
                Spacer()
                
                // Status indicator on the same line
                if game.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 6, height: 6)
                        Text("Inactive")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Game name on separate row
            HStack {
                Text(game.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Actions")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 8) {
                // Refresh button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isRefreshPressed = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isRefreshPressed = false
                        }
                    }
                    
                    fetchGamePlays()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("Refresh")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isRefreshPressed ? Color.blue.opacity(0.7) : Color.blue)
                    .cornerRadius(8)
                    .scaleEffect(isRefreshPressed ? 0.95 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Enable Convo toggle
                HStack(spacing: 8) {
                    Text("Enable Convo")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $isConvoEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .scaleEffect(0.8)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Auto Refresh toggle
                HStack(spacing: 8) {
                    Text("Auto Refresh")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $autoRefresh)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                        .scaleEffect(0.8)
                        .onChange(of: autoRefresh) { newValue in
                            if newValue {
                                startAutoRefresh()
                            } else {
                                stopAutoRefresh()
                            }
                        }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Voice reading field toggle
                HStack(spacing: 8) {
                    Text("Voice Reading:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            readConvoResponse = false
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: readConvoResponse ? "circle" : "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(readConvoResponse ? .gray : .blue)
                                Text("Details")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(readConvoResponse ? .gray : .blue)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            readConvoResponse = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: readConvoResponse ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundColor(readConvoResponse ? .blue : .gray)
                                Text("AI Response")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(readConvoResponse ? .blue : .gray)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Stop speaking button (only show when speaking)
                if ttsService.isSpeaking {
                    Button(action: {
                        ttsService.stopSpeaking()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text("Stop Speaking")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var controlsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Controls")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Seconds per play input
            HStack {
                Text("Seconds per play:")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                TextField("20", value: $secondsPerPlay, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .keyboardType(.numberPad)
                
                Spacer()
            }
            
            
            // Start time controls
            VStack(spacing: 12) {
                HStack {
                    Text("Start Time:")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                // Current start time display
                HStack {
                    Text("Current: \(startTime, format: Date.FormatStyle(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                // Start time buttons - First row
                HStack(spacing: 12) {
                    Button("Now") {
                        startTime = Date()
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Button("5min ago") {
                        startTime = Date().addingTimeInterval(-300) // 5 minutes ago
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Button("10min ago") {
                        startTime = Date().addingTimeInterval(-600) // 10 minutes ago
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Spacer()
                }
                
                // Start time buttons - Second row
                HStack(spacing: 12) {
                    Button("20min ago") {
                        startTime = Date().addingTimeInterval(-1200) // 20 minutes ago
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Button("30min ago") {
                        startTime = Date().addingTimeInterval(-1800) // 30 minutes ago
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Button("40min ago") {
                        startTime = Date().addingTimeInterval(-2400) // 40 minutes ago
                        fetchGamePlays()
                    }
                    .buttonStyle(TimeButtonStyle())
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var gameStatusSection: some View {
        Group {
            if let replayInfo = replayInfo {
                VStack(spacing: 16) {
                    HStack {
                        Text("Game Status")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        // Game status and progress
                        HStack {
                            Text("Status: \(replayInfo.gameStatus)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(replayInfo.currentPlayCount)/\(replayInfo.totalPlayCount) plays")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Progress bar
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Progress")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(String(format: "%.1f", replayInfo.progressPercentage))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            ProgressView(value: replayInfo.progressPercentage, total: 100)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        }
                        
                        // Time information
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Elapsed Time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(replayInfo.elapsedSeconds / 60):\(String(format: "%02d", replayInfo.elapsedSeconds % 60))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Current Time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(replayInfo.currentTime.prefix(19))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    private var gamePlaysSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Game Plays")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if gamePlayAPI.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("\(gamePlays.count) plays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if gamePlayAPI.isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading game plays...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else if gamePlays.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No plays found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Adjust the start time or try refreshing to load game plays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                // Game plays list - show all plays without truncation
                VStack(spacing: 8) {
                    ForEach(gamePlays, id: \.playId) { play in
                        GamePlayRowView(play: play)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func fetchGamePlays() {
        Task {
            do {
                let response = try await gamePlayAPI.fetchGamePlays(
                    gameId: game.gameId,
                    secondsPerPlay: secondsPerPlay,
                    startTime: startTime,
                    convoEnabled: isConvoEnabled,
                    isReplay: game.replay
                )
                
                await MainActor.run {
                    self.gamePlays = response.plays
                    self.replayInfo = response.replayInfo
                    
                    // Auto-speak first play if available
                    if !self.gamePlays.isEmpty {
                        self.speakFirstPlay()
                        self.hasSpokenFirstPlay = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.gamePlayAPI.lastError = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    private func speakFirstPlay() {
        guard let firstPlay = gamePlays.first else { return }
        
        var textToSpeak = ""
        
        if readConvoResponse {
            // Read convoResponse field
            if let convoResponse = firstPlay.convoResponse,
               !convoResponse.isEmpty && convoResponse != "[NO ACTION]" {
                textToSpeak = convoResponse
            }
        } else {
            // Read details field
            let details = firstPlay.details.trimmingCharacters(in: .whitespacesAndNewlines)
            if !details.isEmpty {
                textToSpeak = details
            }
        }
        
        if !textToSpeak.isEmpty {
            ttsService.speak(textToSpeak)
        }
    }
    
    private func startAutoRefresh() {
        stopAutoRefresh() // Stop any existing timer
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { _ in
            print("Auto refresh triggered")
            fetchGamePlays()
        }
        
        print("Auto refresh started - will refresh every 90 seconds")
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("Auto refresh stopped")
    }
}

struct GamePlayRowView: View {
    let play: GamePlayResponse
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Play number, period & clock, down & distance, scores
            HStack(spacing: 8) {
                // Play number
                Text("\(play.playIdInt)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .frame(width: 25, alignment: .leading)
                
                // Period and clock together - more space
                Text("\(play.periodDisplayString) \(play.displayClock)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .leading)
                
                // Down and yards together - more space
                Text("\(downText(play.down)) & \(play.yardsToGo)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(width: 70, alignment: .leading)
                
                Spacer()
                
                // Scores - enough space for two-digit scores on both sides
                Text("\(play.awayScore) : \(play.homeScore)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(width: 60, alignment: .trailing)
                
                // Convo indicator
                if play.convoResponse != nil && play.convoResponse != "[NO ACTION]" {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            // Summary line
            Text(play.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            // Convo response and cost information (if available)
            if let convoResponse = play.convoResponse, !convoResponse.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Response:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text(convoResponse)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Cost information - always show if available
                    if let inputCost = play.inputCost, let outputCost = play.outputCost, let totalCost = play.totalCost {
                        HStack(spacing: 8) {
                            Text("Input: $\(String(format: "%.4f", inputCost))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Output: $\(String(format: "%.4f", outputCost))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Total: $\(String(format: "%.4f", totalCost))")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Bottom row: Full details text (no truncation)
            Text(play.details)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Related News section (if available)
            if let relatedNews = play.relatedNews, !relatedNews.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Text("Related News (\(relatedNews.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(relatedNews.prefix(5).enumerated()), id: \.offset) { index, news in
                                RelatedNewsRowView(news: news)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(.systemGray5))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func downText(_ down: Int) -> String {
        switch down {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "\(down)th"
        }
    }
}

struct RelatedNewsRowView: View {
    let news: RelatedNews
    @State private var isSummaryExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title with score at the beginning
            HStack(alignment: .top, spacing: 8) {
                Text("[\(String(format: "%.2f", news.score))]")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text(news.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            
            // Matched entities
            if !news.entitySimilarity.matchedEntities.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matched Entities:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text(news.entitySimilarity.matchedEntities.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            
            // Collapsible summary - show first 2 lines by default
            VStack(alignment: .leading, spacing: 2) {
                Text(news.summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isSummaryExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show expand/collapse button only if summary is longer than 2 lines
                if news.summary.components(separatedBy: .newlines).count > 2 || 
                   news.summary.count > 100 { // Rough estimate for 2 lines
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSummaryExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isSummaryExpanded ? "Show Less" : "Show More")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                            
                            Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }
}

#Preview {
    NavigationView {
        GameDetailView(game: Game(gameId: "nfl.g.20250823025", name: "PreSeason: LA Chargers vs 49ers", date: Date(), isActive: true))
    }
    .modelContainer(for: [Game.self, GamePlay.self, AudioSegment.self, TextBlock.self], inMemory: true)
}

struct TimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
