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
        convoEnabled: Bool,
        isReplay: Bool = true
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
        
        // Build URL with query parameters - choose endpoint based on isReplay flag
        let endpoint = isReplay ? "replay" : "plays"
        guard var components = URLComponents(string: "\(baseURL)/api/game/\(gameId)/\(endpoint)") else {
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
        print("Using \(isReplay ? "replay" : "plays") endpoint for game: \(gameId)")
        
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
            
            // Create default ReplayInfo if not provided (for plays endpoint)
            let replayInfo = result.replayInfo ?? ReplayInfo(
                gameStatus: result.plays.isEmpty ? "No Plays Available" : "Live",
                currentPlayCount: result.plays.count,
                totalPlayCount: result.plays.count,
                progressPercentage: result.plays.isEmpty ? 0.0 : 100.0,
                elapsedSeconds: 0,
                secondsPerPlay: secondsPerPlay,
                gameStartTime: startTimeString,
                currentTime: startTimeString
            )
            
            print("ReplayInfo: GameStatus=\(replayInfo.gameStatus), CurrentPlayCount=\(replayInfo.currentPlayCount), TotalPlayCount=\(replayInfo.totalPlayCount)")
            
            // Log drives information
            if let drives = result.drives, !drives.isEmpty {
                print("📊 Drives found: \(drives.count)")
                for drive in drives.prefix(3) {
                    print("  - Drive \(drive.driveId): \(drive.team) from \(drive.yardLineText), \(drive.numPlays) plays")
                }
            } else {
                print("📊 No drives found in response")
            }
            
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
            
            return GamePlayAPIResponse(replayInfo: replayInfo, plays: result.plays, drives: result.drives)
        } catch {
            print("JSON parsing error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Missing key '\(key)' in \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch for type \(type) in \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("Value not found for type \(type) in \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw response: \(jsonString)")
            }
            throw GamePlayAPIError.invalidData
        }
    }
}

// MARK: - Data Models

struct GamePlayAPIResponse: Codable {
    let replayInfo: ReplayInfo?
    let plays: [GamePlayResponse]
    let drives: [Drive]? // Handle Drives field
    
    enum CodingKeys: String, CodingKey {
        case replayInfo = "ReplayInfo"
        case plays = "Plays"
        case drives = "Drives"
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
    let driveID: Int?
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
    let playTypeFlag: String? // New field from your response
    
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
        case playTypeFlag = "PlayTypeFlag"
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

struct Drive: Codable {
    let driveId: Int
    let startYardLine: Int
    let totalYards: Int
    let yardLineText: String
    let numPlays: Int
    let startTime: DriveTime
    let endTime: DriveTime
    let timeOfDrive: DriveTime
    let team: String
    let playIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case driveId = "DriveId"
        case startYardLine = "StartYardLine"
        case totalYards = "TotalYards"
        case yardLineText = "YardLineText"
        case numPlays = "NumPlays"
        case startTime = "StartTime"
        case endTime = "EndTime"
        case timeOfDrive = "TimeOfDrive"
        case team = "Team"
        case playIds = "PlayIds"
    }
}

struct DriveTime: Codable {
    let clock: String
    let period: String?
    
    enum CodingKeys: String, CodingKey {
        case clock = "Clock"
        case period = "Period"
    }
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
