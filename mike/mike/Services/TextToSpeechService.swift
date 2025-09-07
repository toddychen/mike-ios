//
//  TextToSpeechService.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation

class TextToSpeechService: NSObject, ObservableObject {
    @Published var isSpeaking = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private let maleVoice: AVSpeechSynthesisVoice?
    
    override init() {
        // Find the best male voice available
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let maleVoices = voices.filter { voice in
            let name = voice.name.lowercased()
            return voice.language.hasPrefix("en") && (
                name.contains("male") || 
                name.contains("man") || 
                name.contains("alex") ||
                name.contains("daniel") ||
                name.contains("aaron") ||
                name.contains("fred") ||
                name.contains("ralph") ||
                name.contains("tom")
            )
        }.sorted { voice1, voice2 in
            // Prefer enhanced voices (higher quality)
            if voice1.quality != voice2.quality {
                return voice1.quality.rawValue > voice2.quality.rawValue
            }
            return voice1.name < voice2.name
        }
        
        self.maleVoice = maleVoices.first
        
        super.init()
        setupAudioSession()
        
        if let voice = maleVoice {
            print("Using male voice: \(voice.name)")
        } else {
            print("No male voice found, will use default")
        }
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
        utterance.voice = maleVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        // Set delegate to track speaking state
        synthesizer.delegate = self
        
        // Start speaking
        synthesizer.speak(utterance)
        isSpeaking = true
        
        print("Speaking with voice: \(utterance.voice?.name ?? "Default")")
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
