//
//  TextToSpeechService.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation

class TextToSpeechService: ObservableObject {
    @Published var isSpeaking = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    init() {
        setupAudioSession()
    }
    
    /// Speak the provided text
    func speak(_ text: String) {
        // Stop any current speech
        stopSpeaking()
        
        // Validate input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        // Set delegate to track speaking state
        synthesizer.delegate = self
        
        // Start speaking
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    /// Stop current speech
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("TextToSpeech: Failed to configure audio session: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
