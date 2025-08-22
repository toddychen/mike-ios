//
//  TextBlock.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import SwiftData

@Model
final class TextBlock {
    var id: String
    var startTime: Date
    var lastUpdateTime: Date
    var content: String
    var totalDuration: TimeInterval
    var segmentCount: Int
    var isCompleted: Bool
    
    init(id: String = UUID().uuidString, startTime: Date = Date(), content: String = "", totalDuration: TimeInterval = 0, segmentCount: Int = 0, isCompleted: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.lastUpdateTime = startTime
        self.content = content
        self.totalDuration = totalDuration
        self.segmentCount = segmentCount
        self.isCompleted = isCompleted
    }
    
    func appendText(_ newText: String, duration: TimeInterval) {
        if !content.isEmpty {
            content += " " // Add space between segments
        }
        content += newText
        totalDuration += duration
        segmentCount += 1
        lastUpdateTime = Date()
        
        // Mark as completed if text is long enough (e.g., > 200 characters, roughly 2-3 sentences)
        if content.count > 200 {
            isCompleted = true
        }
    }
}
