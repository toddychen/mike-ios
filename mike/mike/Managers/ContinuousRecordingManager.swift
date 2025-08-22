//
//  ContinuousRecordingManager.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import SwiftData
import Combine
import AVFoundation

@MainActor
class ContinuousRecordingManager: ObservableObject {
    @Published var isContinuousRecording = false
    @Published var currentPhase = RecordingPhase.listening
    @Published var transcriptionStatus = TranscriptionStatus.idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingTime: TimeInterval = 0.0
    
    // Core components
    private let audioListener = AudioListener()
    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    
    // Global audio session management
    private let audioSession = AVAudioSession.sharedInstance()
    
    // Database context
    private var modelContext: ModelContext?
    
    // Event handling
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Enums
    
    enum RecordingPhase {
        case listening      // 正在监听
        case recording      // 正在录音
        case processing     // 处理录音
        case stopped        // 已停止
        
        var description: String {
            switch self {
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
        setupEventHandlers()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Event Handlers Setup
    
    private func setupEventHandlers() {
        // AudioListener 触发录音
        audioListener.onRecordingTriggered = { [weak self] historyData in
            print("Manager: Received recording trigger from Listener")
            self?.startRecording(withHistoryData: historyData)
        }
        
        // AudioRecorder 完成录音
        audioRecorder.onRecordingFinished = { [weak self] audioURL, duration in
            print("Manager: Received recording finished from Recorder")
            self?.handleRecordingFinished(audioURL: audioURL, duration: duration)
        }
        
        // 监听状态变化
        audioListener.$isListening
            .sink { [weak self] isListening in
                self?.updatePhase(isListening: isListening)
            }
            .store(in: &cancellables)
        
        audioRecorder.$isRecording
            .sink { [weak self] isRecording in
                self?.updatePhase(isRecording: isRecording)
            }
            .store(in: &cancellables)
        
        // 监听音频电平变化
        audioListener.$audioLevel
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)
        
        // 监听录音时间变化
        audioRecorder.$recordingTime
            .sink { [weak self] time in
                self?.recordingTime = time
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Interface
    
    func toggleContinuousRecording() {
        if isContinuousRecording {
            stopContinuousRecording()
        } else {
            startContinuousRecording()
        }
    }
    
    func startContinuousRecording() {
        isContinuousRecording = true
        currentPhase = .listening
        transcriptionStatus = .idle
        
        print("=== ContinuousRecordingManager: Starting continuous recording mode ===")
        
        // Setup global audio session
        setupGlobalAudioSession()
        startListening()
    }
    
    func stopContinuousRecording() {
        isContinuousRecording = false
        currentPhase = .stopped
        transcriptionStatus = .idle
        
        print("=== ContinuousRecordingManager: Stopping continuous recording mode ===")
        
        // Stop current recording if active
        if audioRecorder.isRecording {
            _ = audioRecorder.stopRecording()
        }
        
        // Stop audio listening if active
        if audioListener.isListening {
            audioListener.stopListening()
        }
        
        // Clean up resources
        audioRecorder.cleanupRecorder()
        
        // Deactivate audio session
        deactivateAudioSession()
    }
    
    // MARK: - Phase Management
    
    private func updatePhase(isListening: Bool) {
        if isListening {
            currentPhase = .listening
        } else if audioRecorder.isRecording {
            currentPhase = .recording
        } else if currentPhase != .stopped {
            currentPhase = .processing
        }
    }
    
    private func updatePhase(isRecording: Bool) {
        if isRecording {
            currentPhase = .recording
        } else if audioListener.isListening {
            currentPhase = .listening
        } else if currentPhase != .stopped {
            currentPhase = .processing
        }
    }
    
    // MARK: - Core Flow Control
    
    private func startListening() {
        guard isContinuousRecording else { return }
        
        print("Manager: Starting audio listener")
        currentPhase = .listening
        audioListener.startListening()
    }
    
    // MARK: - Audio Session Management
    
    private func setupGlobalAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            print("=== ContinuousRecordingManager: Global audio session configured for .playAndRecord ===")
        } catch {
            print("ERROR: Failed to setup global audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false)
            print("=== ContinuousRecordingManager: Audio session deactivated ===")
        } catch {
            print("ERROR: Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Core Flow Control
    
    private func startRecording(withHistoryData: [Float]) {
        guard isContinuousRecording else { return }
        
        // 记录Manager收到触发的时间
        let triggerReceivedTime = Date().timeIntervalSince1970
        print("📡 MANAGER RECEIVED TRIGGER at: \(triggerReceivedTime) (\(String(format: "%.3f", triggerReceivedTime)))")
        
        print("Manager: Starting recording with \(withHistoryData.count) samples of history")
        currentPhase = .recording
        audioRecorder.startRecording(withHistoryData: withHistoryData)
    }
    
    private func handleRecordingFinished(audioURL: URL, duration: TimeInterval) {
        print("Manager: Recording finished, duration received: \(duration)s")
        
        // 立即启动下一个监听循环
        startListening()
        
        // 异步处理录音文件
        Task {
            await processRecordingAsync(audioURL: audioURL, duration: duration)
        }
    }
    
    // MARK: - Async Recording Processing
    
    private func processRecordingAsync(audioURL: URL, duration: TimeInterval) async {
        print("Manager: Processing recording asynchronously...")
        transcriptionStatus = .processing
        
        do {
            // 发送到服务器进行转录
            let transcribedText = try await transcriptionService.transcribeAudio(audioURL: audioURL)
            
            // 异步保存到数据库
            await saveTranscription(text: transcribedText, duration: duration, audioURL: audioURL)
            
            print("Manager: Transcription completed: \(transcribedText.prefix(50))...")
            
            // 更新转录状态
            transcriptionStatus = .completed
            
            // 延迟后重置转录状态
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒后重置
            transcriptionStatus = .idle
            
        } catch {
            print("Manager: Transcription failed: \(error)")
            
            // 异步保存失败记录
            await saveTranscription(text: "Transcription failed", duration: duration, isSuccess: false, audioURL: audioURL)
            
            // 更新转录状态
            transcriptionStatus = .failed
            
            // 延迟后重置转录状态
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒后重置
            transcriptionStatus = .idle
        }
        
        // 确保文件被保存到永久位置
        await ensureFilePersistence(audioURL: audioURL)
        
        // 暂时不删除音频文件，保留用于测试和验证
        // 在实际应用中，您可能想要提供手动删除选项或设置保留策略
        print("Manager: Audio file retained for testing: \(audioURL.lastPathComponent)")
        // cleanupAudioFile(audioURL) // 暂时注释掉
    }
    
    // MARK: - Database Operations
    
    private func saveTranscription(text: String, duration: TimeInterval, isSuccess: Bool = true, audioURL: URL? = nil) async {
        guard let modelContext = modelContext else { return }
        
        // Save individual transcription record
        print("Manager: Creating AudioSegment with duration: \(duration)s")
        let audioSegment = AudioSegment(
            timestamp: Date(),
            transcribedText: text,
            duration: duration,
            isSuccess: isSuccess,
            audioFilePath: audioURL?.absoluteString
        )
        
        // Get or create text block
        let textBlock = await getOrCreateTextBlock(context: modelContext)
        
        // Link audio segment to text block
        audioSegment.textBlockId = textBlock.id
        
        // Append text to text block
        textBlock.appendText(text, duration: duration)
        
        // Save both to database
        modelContext.insert(audioSegment)
        
        do {
            try modelContext.save()
            print("Manager: Saved transcription to database: \(text.prefix(50))...")
            if let audioPath = audioURL?.absoluteString {
                print("Manager: Audio file path saved: \(audioPath)")
            }
        } catch {
            print("Manager: Failed to save: \(error)")
        }
    }
    
    private func getOrCreateTextBlock(context: ModelContext) async -> TextBlock {
        // Try to find an incomplete text block
        let descriptor = FetchDescriptor<TextBlock>(
            predicate: #Predicate<TextBlock> { text in
                !text.isCompleted
            },
            sortBy: [SortDescriptor(\.lastUpdateTime, order: .reverse)]
        )
        
        do {
            let existingBlocks = try context.fetch(descriptor)
            if let latestBlock = existingBlocks.first {
                return latestBlock
            }
        } catch {
            print("Manager: Failed to fetch text block: \(error)")
        }
        
        // Create new text block if none exists or all are completed
        let newBlock = TextBlock()
        context.insert(newBlock)
        return newBlock
    }
    
    // MARK: - File Management
    
    private func ensureFilePersistence(audioURL: URL) async {
        // Ensure the audio file is saved to a permanent location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let permanentFileName = "permanent_\(Date().timeIntervalSince1970).m4a"
        let permanentURL = documentsPath.appendingPathComponent(permanentFileName)
        
        do {
            // Copy file to permanent location if it doesn't exist
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.copyItem(at: audioURL, to: permanentURL)
                print("Manager: Audio file copied to permanent location: \(permanentURL.lastPathComponent)")
                
                // Update the audioURL to point to the permanent file
                // Note: This is a simplified approach - in a real app you might want to update the database
                print("Manager: Original file: \(audioURL.lastPathComponent)")
                print("Manager: Permanent file: \(permanentURL.lastPathComponent)")
            } else {
                print("Manager: Warning: Original audio file not found at: \(audioURL.path)")
            }
        } catch {
            print("Manager: Failed to ensure file persistence: \(error)")
        }
    }
    
    private func cleanupAudioFile(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("Manager: Audio file cleaned up: \(fileURL.lastPathComponent)")
        } catch {
            print("Manager: Failed to cleanup audio file: \(error)")
        }
    }
    

    
    // MARK: - Status Access
    
    var currentStatus: String {
        return currentPhase.description
    }
    
    var isListening: Bool {
        return audioListener.isListening
    }
    
    var isRecording: Bool {
        return audioRecorder.isRecording
    }
        
    // recordingTime 现在是 @Published 属性，直接使用
}
