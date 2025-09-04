//
//  GamePlay.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import SwiftData

@Model
final class GamePlay {
    var id: String
    var gameId: String
    var playNumber: Int
    var quarter: Int
    var timeRemaining: String
    var down: Int
    var distance: Int
    var playDescription: String
    var timestamp: Date
    
    init(id: String = UUID().uuidString, gameId: String, playNumber: Int, quarter: Int, timeRemaining: String, down: Int, distance: Int, description: String, timestamp: Date = Date()) {
        self.id = id
        self.gameId = gameId
        self.playNumber = playNumber
        self.quarter = quarter
        self.timeRemaining = timeRemaining
        self.down = down
        self.distance = distance
        self.playDescription = description
        self.timestamp = timestamp
    }
}
