//
//  ContinuousAudioManager.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation
import Combine
import SwiftData

@MainActor
class ContinuousAudioManager: ObservableObject {
    @Published var isRecording = false
    @Published var currentPhase = RecordingPhase.idle
    @Published var transcriptionStatus = TranscriptionStatus.idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingTime: TimeInterval = 0.0
    
    // Dual recorder system
    private var recorderA: AudioRecorder
    private var recorderB: AudioRecorder
    private var activeRecorder: AudioRecorder
    private var standbyRecorder: AudioRecorder
    private var currentRecorderIndex = 0
    
    // Global audio session management
    private let audioSession = AVAudioSession.sharedInstance()
    
    // Database context
    private var modelContext: ModelContext?
    
    // Current text block for organizing transcriptions
    private var currentTextBlock: TextBlock?
    
    // Event handling
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Enums
    
    enum RecordingPhase {
        case idle           // 空闲
        case listening      // 正在监听
        case recording      // 正在录音
        case processing     // 处理录音
        case stopped        // 已停止
        
        var description: String {
            switch self {
            case .idle: return "Idle"
            case .listening: return "Listening for audio activity"
            case .recording: return "Recording audio"
            case .processing: return "Processing recording"
            case .stopped: return "Recording stopped"
            }
        }
    }
    
    enum TranscriptionStatus {
        case idle           // 空闲
        case processing     // 正在转录
        case completed      // 转录完成
        case failed         // 转录失败
        
        var description: String {
            switch self {
            case .idle: return "Idle"
            case .processing: return "Processing transcription"
            case .completed: return "Transcription completed"
            case .failed: return "Transcription failed"
            }
        }
    }
    
    init() {
        // Initialize dual recorders
        recorderA = AudioRecorder()
        recorderB = AudioRecorder()
        
        // Set initial active and standby recorders
        activeRecorder = recorderA
        standbyRecorder = recorderB
        
        setupEventHandlers()
        setupRecorderCallbacks()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        recorderA.setModelContext(context)
        recorderB.setModelContext(context)
        
        // Recorders are already prepared during initialization
        print("ModelContext set for both recorders")
    }
    
    // MARK: - Event Handlers Setup
    
    private func setupEventHandlers() {
        // Listen to audio level changes from active recorder
        activeRecorder.$audioLevel
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)
        
        // Listen to recording time changes from active recorder
        activeRecorder.$recordingTime
            .sink { [weak self] time in
                self?.recordingTime = time
            }
            .store(in: &cancellables)
    }
    
    private func setupRecorderCallbacks() {
        // Setup callbacks for both recorders
        setupRecorderCallbacks(for: recorderA)
        setupRecorderCallbacks(for: recorderB)
    }
    
    private func setupRecorderCallbacks(for recorder: AudioRecorder) {
        // Recording finished callback
        recorder.onRecordingFinished = { [weak self] audioURL, duration in
            print("Recorder finished recording: \(audioURL.lastPathComponent), duration: \(duration)s")
            self?.handleRecordingFinished(audioURL: audioURL, duration: duration)
        }
        
        // State change callback
        recorder.onStateChanged = { [weak self] newState in
            print("Recorder state changed to: \(newState)")
            self?.updatePhase()
        }
    }
    
    // MARK: - Public Interface
    
    func toggleContinuousRecording() {
        if isRecording {
            stopContinuousRecording()
        } else {
            startContinuousRecording()
        }
    }
    
    func startContinuousRecording() {
        isRecording = true
        currentPhase = .listening
        transcriptionStatus = .idle
        
        // Reset current text block for new session
        currentTextBlock = nil
        
        print("=== ContinuousAudioManager: Starting continuous recording mode ===")
        
        // 1. First activate audio session (setup audio environment)
        activateAudioSession()
        
        // 2. Then reset both recorders (after audio session is ready)
        resetBothRecorders()
        
        // 3. Finally start listening (ensure recorders are prepared)
        startListening()
    }
    
    func stopContinuousRecording() {
        isRecording = false
        currentPhase = .stopped
        transcriptionStatus = .idle
        
        print("=== ContinuousAudioManager: Stopping continuous recording mode ===")
        
        // Stop current recording if active
        if activeRecorder.state == .recording {
            _ = activeRecorder.stopRecording()
        }
        
        // Stop listening
        stopListening()
        
        // Deactivate audio session
        deactivateAudioSession()
        

    }
    
    // MARK: - Audio Session Management
    
    private func activateAudioSession() {
        do {
            // First ensure the category is set to .playAndRecord for recording
            try audioSession.setCategory(.playAndRecord, mode: .default)
            
            // Then activate the session
            try audioSession.setActive(true)
            print("=== ContinuousAudioManager: Audio session activated for recording ===")
        } catch {
            print("ERROR: Failed to activate audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false)
            print("=== ContinuousAudioManager: Audio session deactivated ===")
        } catch {
            print("ERROR: Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Core Flow Control
    
    private func startListening() {
        guard isRecording else { 
            print("ERROR: Cannot start listening - isRecording is false")
            return 
        }
        
        print("Manager: Starting audio listening")
        currentPhase = .listening
        
        // Start listening with active recorder
        activeRecorder.startListening()
        
        print("Manager: Listening started")
    }
    
    private func stopListening() {
        print("Manager: Stopping audio listening")
        
        // Stop listening with active recorder
        activeRecorder.stopListening()
    }
    
    private func handleRecordingFinished(audioURL: URL, duration: TimeInterval) {
        print("Manager: Recording finished, duration: \(duration)s")
        
        // Switch recorders for continuous recording
        switchRecorders()
        
        // Start next listening cycle immediately for better responsiveness
        startListening()
        
        // Prepare the new standby recorder for next use
        standbyRecorder.prepareForNextRecording()
        
        // Process the completed recording asynchronously
        Task {
            print("Starting async processing for file: \(audioURL.lastPathComponent)")
            await processRecordingAsync(audioURL: audioURL, duration: duration)
        }
        
        print("Recording finished handling completed")
    }
    
    private func resetBothRecorders() {
        print("=== Resetting both recorders for new recording cycle ===")
        
        // Always reset both recorders to clean state
        activeRecorder.cleanup()
        activeRecorder.prepareForNextRecording()
        
        standbyRecorder.cleanup()
        standbyRecorder.prepareForNextRecording()
        
        // Reset recorder selection to initial state
        activeRecorder = recorderA
        standbyRecorder = recorderB
        currentRecorderIndex = 0
        
        print("Both recorders reset and ready for new cycle")
    }
    
    private func switchRecorders() {
        print("=== Switching recorders ===")
        
        // Swap active and standby recorders
        let temp = activeRecorder
        activeRecorder = standbyRecorder
        standbyRecorder = temp
        
        // Update index
        currentRecorderIndex = (currentRecorderIndex + 1) % 2
        
        print("Switched to \(currentRecorderIndex == 0 ? "recorderA" : "recorderB")")
        
        // Update event handlers for new active recorder
        setupEventHandlers()
        
        // Ensure the new active recorder is in listening state if it was recording
        if activeRecorder.state == .recording {
            print("WARNING: New active recorder was in recording state, resetting to standby")
            activeRecorder.cleanup()
            activeRecorder.prepareForNextRecording()
        }
    }
    
    // MARK: - Phase Management
    
    private func updatePhase() {
        if activeRecorder.state == .recording {
            currentPhase = .recording
        } else if activeRecorder.state == .listening {
            currentPhase = .listening
        } else if activeRecorder.state == .processing {
            currentPhase = .processing
        } else if !isRecording {
            currentPhase = .stopped
        }
    }
    
    // MARK: - Async Recording Processing
    
    private func processRecordingAsync(audioURL: URL, duration: TimeInterval) async {
        print("Manager: Processing recording asynchronously...")
        transcriptionStatus = .processing
        
        do {
            // Send to server for transcription
            let transcriptionService = TranscriptionService()
            print("Manager: Sending audio to transcription service...")
            let transcribedText = try await transcriptionService.transcribeAudio(audioURL: audioURL)
            
            print("Manager: Received transcription: \(transcribedText)")
            
            // Save to database
            await saveTranscription(text: transcribedText, duration: duration, audioURL: audioURL)
            
            print("Manager: Transcription completed: \(transcribedText.prefix(50))...")
            
            // Update transcription status
            transcriptionStatus = .completed
            
            // Reset transcription status after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            transcriptionStatus = .idle
            
        } catch {
            print("Manager: Transcription failed: \(error)")
            
            // Save failure record
            await saveTranscription(text: "Transcription failed", duration: duration, isSuccess: false, audioURL: audioURL)
            
            // Update transcription status
            transcriptionStatus = .failed
            
            // Reset transcription status after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            transcriptionStatus = .idle
        }
        
        // Ensure file persistence
        await ensureFilePersistence(audioURL: audioURL)
        
        print("Manager: Audio file retained: \(audioURL.lastPathComponent)")
    }
    
    // MARK: - Database Operations
    
    private func saveTranscription(text: String, duration: TimeInterval, isSuccess: Bool = true, audioURL: URL? = nil) async {
        guard let modelContext = modelContext else { return }
        
        // Create or get current text block
        if currentTextBlock == nil {
            currentTextBlock = TextBlock(
                startTime: Date(),
                content: "",
                totalDuration: 0,
                segmentCount: 0,
                isCompleted: false
            )
            modelContext.insert(currentTextBlock!)
            print("Manager: Created new TextBlock")
        }
        
        // Save individual transcription record
        print("Manager: Creating AudioSegment with duration: \(duration)s")
        let audioSegment = AudioSegment(
            timestamp: Date(),
            transcribedText: text,
            duration: duration,
            isSuccess: isSuccess,
            audioFilePath: audioURL?.absoluteString
        )
        
        modelContext.insert(audioSegment)
        
        // Update text block with new content
        if isSuccess && !text.isEmpty {
            // Check if current text block is completed or needs to be created
            if currentTextBlock == nil || currentTextBlock?.isCompleted == true {
                // Create new text block
                currentTextBlock = TextBlock(
                    startTime: Date(),
                    content: "",
                    totalDuration: 0,
                    segmentCount: 0,
                    isCompleted: false
                )
                modelContext.insert(currentTextBlock!)
                print("Manager: Created new TextBlock (previous was completed or nil)")
            }
            
            // Append text to current block
            currentTextBlock?.appendText(text, duration: duration)
            print("Manager: Updated TextBlock with new text: \(text.prefix(50))...")
            
            // Check if text block is now completed
            if currentTextBlock?.isCompleted == true {
                print("Manager: TextBlock completed (length: \(currentTextBlock?.content.count ?? 0) characters)")
            }
        }
        
        // Try to save
        do {
            try modelContext.save()
            print("Manager: AudioSegment and TextBlock saved successfully")
        } catch {
            print("Manager: Failed to save: \(error)")
        }
    }
    
    private func ensureFilePersistence(audioURL: URL) async {
        // Ensure the audio file is saved to a permanent location
        // This is already handled by the AudioRecorder
        print("Manager: File persistence ensured for: \(audioURL.lastPathComponent)")
    }
}
