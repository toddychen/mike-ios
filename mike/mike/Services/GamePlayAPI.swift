//
//  GamePlayAPI.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation

class GamePlayAPI: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    
    private let baseURL = "http://192.168.86.32:3000"
    
    func fetchGamePlays(
        gameId: String,
        secondsPerPlay: Int,
        startTime: Date,
        convoEnabled: Bool
    ) async throws -> GamePlayAPIResponse {
        
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Format start time for API
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let startTimeString = formatter.string(from: startTime)
        
        // Build URL with query parameters
        guard var components = URLComponents(string: "\(baseURL)/api/game/\(gameId)/replay") else {
            throw GamePlayAPIError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "seconds_per_play", value: "\(secondsPerPlay)"),
            URLQueryItem(name: "start", value: startTimeString),
            URLQueryItem(name: "convo", value: convoEnabled ? "true" : "false")
        ]
        
        guard let url = components.url else {
            throw GamePlayAPIError.invalidURL
        }
        
        print("Fetching game plays from: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GamePlayAPIError.invalidResponse
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("API Error: \(errorMessage)")
            throw GamePlayAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse JSON response
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(GamePlayAPIResponse.self, from: data)
            print("Successfully fetched \(result.plays.count) game plays")
            print("ReplayInfo: GameStatus=\(result.replayInfo.gameStatus), CurrentPlayCount=\(result.replayInfo.currentPlayCount), TotalPlayCount=\(result.replayInfo.totalPlayCount)")
            
            // Log detailed play information for first play only
            if result.plays.isEmpty {
                print("⚠️ No plays found in response")
            } else {
                print("📊 Plays found: \(result.plays.count)")
                
                // Log detailed information for first play only
                if let firstPlay = result.plays.first {
                    print("🎯 First Play Details:")
                    print("  - PlayId: \(firstPlay.playId)")
                    print("  - Down: \(firstPlay.down)")
                    print("  - YardsToGo: \(firstPlay.yardsToGo)")
                    print("  - Period: \(firstPlay.period)")
                    print("  - DisplayClock: \(firstPlay.displayClock)")
                    print("  - Summary: \(firstPlay.summary)")
                    print("  - Details: \(firstPlay.details)")
                    
                    print("  - ConvoResponse: \(firstPlay.convoResponse ?? "nil")")
                    print("  - InputCost: \(firstPlay.inputCost ?? 0)")
                    print("  - OutputCost: \(firstPlay.outputCost ?? 0)")
                    print("  - TotalCost: \(firstPlay.totalCost ?? 0)")
                }
                
                if result.plays.count > 1 {
                    print("  ... and \(result.plays.count - 1) more plays")
                }
            }
            
            return result
        } catch {
            print("JSON parsing error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw response: \(jsonString)")
            }
            throw GamePlayAPIError.invalidData
        }
    }
}

// MARK: - Data Models

struct GamePlayAPIResponse: Codable {
    let replayInfo: ReplayInfo
    let plays: [GamePlayResponse]
    
    enum CodingKeys: String, CodingKey {
        case replayInfo = "ReplayInfo"
        case plays = "Plays"
    }
}

struct ReplayInfo: Codable {
    let gameStatus: String
    let currentPlayCount: Int
    let totalPlayCount: Int
    let progressPercentage: Double
    let elapsedSeconds: Int
    let secondsPerPlay: Int
    let gameStartTime: String
    let currentTime: String
    
    enum CodingKeys: String, CodingKey {
        case gameStatus = "GameStatus"
        case currentPlayCount = "CurrentPlayCount"
        case totalPlayCount = "TotalPlayCount"
        case progressPercentage = "ProgressPercentage"
        case elapsedSeconds = "ElapsedSeconds"
        case secondsPerPlay = "SecondsPerPlay"
        case gameStartTime = "GameStartTime"
        case currentTime = "CurrentTime"
    }
}

struct GamePlayResponse: Codable {
    let down: Int
    let yardsToGo: Int
    let ballSpotYard: Int
    let period: Int
    let playTime: Int
    let periodDisplayString: String
    let ballSpotField: String
    let driveID: Int
    let review: Bool
    let yardsOnPlay: Int
    let continuation: Bool
    let homeTeamOnOffense: Bool
    let team: String
    let displayClock: String
    let summary: String
    let playId: String
    let details: String
    let homeScore: Int
    let awayScore: Int
    let scoringPlay: Bool
    let periodNum: Int
    let sportType: String
    let playIdInt: Int
    let lastXPlays: String?
    let relatedNews: [RelatedNews]?
    let convoResponse: String?
    let inputCost: Double?
    let outputCost: Double?
    let totalCost: Double?
    let playType: String?
    let playDirection: String?
    let playerId1: String?
    let playerId2: String?
    let awayHome: String?
    
    enum CodingKeys: String, CodingKey {
        case down = "Down"
        case yardsToGo = "YardsToGo"
        case ballSpotYard = "BallSpotYard"
        case period = "Period"
        case playTime = "PlayTime"
        case periodDisplayString = "PeriodDisplayString"
        case ballSpotField = "BallSpotField"
        case driveID = "DriveID"
        case review = "Review"
        case yardsOnPlay = "YardsOnPlay"
        case continuation = "Continuation"
        case homeTeamOnOffense = "HomeTeamOnOffense"
        case team = "Team"
        case displayClock = "DisplayClock"
        case summary = "Summary"
        case playId = "PlayId"
        case details = "Details"
        case homeScore = "HomeScore"
        case awayScore = "AwayScore"
        case scoringPlay = "ScoringPlay"
        case periodNum = "PeriodNum"
        case sportType = "SportType"
        case playIdInt = "PlayIdInt"
        case lastXPlays = "LastXPlays"
        case relatedNews = "RelatedNews"
        case convoResponse = "ConvoResponse"
        case inputCost = "InputCost"
        case outputCost = "OutputCost"
        case totalCost = "TotalCost"
        case playType = "PlayType"
        case playDirection = "PlayDirection"
        case playerId1 = "PlayerId1"
        case playerId2 = "PlayerId2"
        case awayHome = "AwayHome"
    }
}

struct RelatedNews: Codable {
    let title: String
    let summary: String
    let score: Double
    let entitySimilarity: EntitySimilarity
    
    enum CodingKeys: String, CodingKey {
        case title, summary, score
        case entitySimilarity = "entity_similarity"
    }
}

struct EntitySimilarity: Codable {
    let score: Double
    let playEntityCount: Int
    let newsEntityCount: Int
    let matchedCount: Int
    let matchedEntities: [String]
    let playEntities: [Entity]
    let newsEntities: [Entity]
    
    enum CodingKeys: String, CodingKey {
        case score
        case playEntityCount = "play_entity_count"
        case newsEntityCount = "news_entity_count"
        case matchedCount = "matched_count"
        case matchedEntities = "matched_entities"
        case playEntities = "play_entities"
        case newsEntities = "news_entities"
    }
}

struct Entity: Codable {
    let text: String
    let confidence: Double
}

// MARK: - Error Handling

enum GamePlayAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case invalidData
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let statusCode, let message):
            return "Server error \(statusCode): \(message)"
        case .invalidData:
            return "Invalid data format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
