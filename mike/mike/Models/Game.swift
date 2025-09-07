//
//  Game.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import SwiftData

@Model
final class Game {
    var gameId: String
    var name: String
    var date: Date
    var isActive: Bool
    var replay: Bool
    
    init(gameId: String, name: String, date: Date, isActive: Bool = false, replay: Bool = true) {
        self.gameId = gameId
        self.name = name
        self.date = date
        self.isActive = isActive
        self.replay = replay
    }
}
