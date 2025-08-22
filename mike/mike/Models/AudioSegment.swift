//
//  Item.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import SwiftData

@Model
final class AudioSegment {
    var timestamp: Date
    var transcribedText: String
    var duration: TimeInterval
    var isSuccess: Bool
    var textBlockId: String? // Link to text block
    
    // Additional fields from server response
    var language: String?
    var filename: String?
    var model: String?
    var method: String?
    var performanceMetrics: String? // JSON string for performance metrics
    
    // Local audio file path for playback
    var audioFilePath: String?
    
    init(timestamp: Date, transcribedText: String = "", duration: TimeInterval = 0, isSuccess: Bool = false, textBlockId: String? = nil, language: String? = nil, filename: String? = nil, model: String? = nil, method: String? = nil, performanceMetrics: String? = nil, audioFilePath: String? = nil) {
        self.timestamp = timestamp
        self.transcribedText = transcribedText
        self.duration = duration
        self.isSuccess = isSuccess
        self.textBlockId = textBlockId
        self.language = language
        self.filename = filename
        self.model = model
        self.method = method
        self.performanceMetrics = performanceMetrics
        self.audioFilePath = audioFilePath
    }
}
