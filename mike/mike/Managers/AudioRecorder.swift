//
//  AudioRecorder.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation
import Combine
import SwiftData

class AudioRecorder: NSObject, ObservableObject {
    @Published var state: RecorderState = .standby
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    
    // Audio Engine for listening and recording
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    
    // File management
    private var currentFileURL: URL?
    private var tempHistoryFile: URL?
    
    // Audio buffer for history - will be adjusted based on device sample rate
    private var audioBuffer: [Float] = []
    private var bufferIndex = 0
    private var isBufferFull = false
    
    // Audio level detection control
    private var lastCalculationTime: TimeInterval = 0
    
    // Timers
    private var recordingTimer: Timer?
    private var silenceTimer: Timer?
    
    // Configuration parameters
    let maxRecordingDuration: TimeInterval = 20.0 // Maximum recording duration 20 seconds
    let silenceThreshold: TimeInterval = 2.0 // Silence detection threshold 2 seconds
    let silenceLevel: Float = -45.0 // Silence level threshold in dB
    let calculationInterval: TimeInterval = 0.02 // 20ms for faster response
    
    // Event callbacks
    var onRecordingFinished: ((URL, TimeInterval) -> Void)?
    var onStateChanged: ((RecorderState) -> Void)?
    
    // Database context
    private var modelContext: ModelContext?
    
    // MARK: - Enums
    
    enum RecorderState {
        case standby      // 待命，文件已创建，准备录音
        case listening    // 正在监听音频活动
        case recording    // 正在录音
        case processing   // 正在处理上传/转录
        
        var description: String {
            switch self {
            case .standby: return "Standby"
            case .listening: return "Listening"
            case .recording: return "Recording"
            case .processing: return "Processing"
            }
        }
    }
    
    override init() {
        super.init()
        
        // Prepare the recorder immediately after initialization
        print("=== AudioRecorder: Initializing and preparing ===")
        setupAudioEngine()  // Setup engine first
        resetAudioBuffer()  // Then reset buffer with correct size
        createAudioFile()   // Finally create file with correct format
        
        updateState(.standby)
        print("=== AudioRecorder: Initialization completed ===")
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Public Interface
    
    func startListening() {
        guard state == .standby else { return }
        
        print("=== AudioRecorder: Starting listening mode ===")
        
        // Check if we're already prepared
        if audioEngine == nil || inputNode == nil || audioFile == nil {
            print("ERROR: Recorder not prepared, cannot start listening")
            return
        }
        
        // Start audio engine if not already running
        if audioEngine?.isRunning == false {
            do {
                try audioEngine?.start()
                print("Audio engine started successfully")
            } catch {
                print("ERROR: Failed to start audio engine: \(error)")
                return
            }
        }
        
        updateState(.listening)
        print("Listening mode started successfully")
    }
    
    func stopListening() {
        guard state == .listening else { return }
        
        print("=== AudioRecorder: Stopping listening mode ===")
        
        // Stop audio engine
        stopAudioEngine()
        
        // Close audio file
        audioFile = nil
        
        updateState(.standby)
        print("Listening mode stopped")
    }
    
    func startRecording() {
        guard state == .listening else { return }
        
        print("=== AudioRecorder: Starting recording ===")
        
        // Start recording timer
        startRecordingTimer()
        
        updateState(.recording)
        print("Recording started successfully")
    }
    
    func stopRecording() -> URL? {
        guard state == .recording else { return nil }
        
        print("=== AudioRecorder: Stopping recording ===")
        print("Recording duration: \(recordingTime)s")
        
        // Stop timers
        stopRecordingTimer()
        stopSilenceTimer()
        
        // Get duration
        let duration = recordingTime
        
        // Close audio file
        let recordingURL = currentFileURL
        audioFile = nil
        
        // Reset recording time
        recordingTime = 0
        
        // Update state
        updateState(.processing)
        
        print("Recording stopped after \(duration)s")
        print("Recording file: \(recordingURL?.absoluteString ?? "nil")")
        
        // Call callback
        if let url = recordingURL {
            onRecordingFinished?(url, duration)
        }
        
        return recordingURL
    }
    
    func prepareForNextRecording() {
        print("=== AudioRecorder: Preparing for next recording ===")
        
        // 1. First setup audio engine (to get inputNode)
        if audioEngine == nil {
            setupAudioEngine()
        }
        
        // 2. Validate that inputNode is ready with valid format
        guard let inputNode = inputNode else {
            print("ERROR: Input node not available for file creation")
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.prepareForNextRecording()
            }
            return
        }
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("ERROR: Input format not ready - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.prepareForNextRecording()
            }
            return
        }
        
        // 3. Then create audio file (inputNode is now available)
        createAudioFile()
        
        // 4. Finally reset audio buffer
        resetAudioBuffer()
        
        // Update state to standby
        updateState(.standby)
        
        print("Recorder prepared and ready for next recording")
    }
    
    // MARK: - Audio Engine Management
    
    private func setupAudioEngine() {
        print("Setting up audio engine...")
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("ERROR: Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("ERROR: Failed to get input node")
            return
        }
        
        // Use device native format to avoid format mismatch
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Device input format: \(inputFormat)")
        
        // Validate format before installing tap
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("ERROR: Invalid input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
            print("Audio session may not be ready for recording. Retrying in 0.5 seconds...")
            
            // Retry after a delay to allow audio session to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupAudioEngine()
            }
            return
        }
        
        // Install tap with device native format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            // print("Audio buffer received - format: \(buffer.format), frameLength: \(buffer.frameLength), sampleRate: \(buffer.format.sampleRate)")
            self?.processAudioBuffer(buffer)
        }
        
        // Don't start engine yet - wait for startListening() call
        print("Audio engine setup completed, ready to start")
    }
    
    private func stopAudioEngine() {
        print("Stopping audio engine...")
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        
        audioEngine = nil
        inputNode = nil
        
        print("Audio engine stopped")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Always fill audio buffer
        fillAudioBuffer(buffer)
        
        // 2. Always write to audio file if recording
        if let audioFile = audioFile, state == .recording {
            // print("Writing buffer to file - format: \(buffer.format), sampleRate: \(buffer.format.sampleRate)")
            try? audioFile.write(from: buffer)
        }
        
        // 3. Check audio level at specified intervals
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastCalculationTime >= calculationInterval {
            let level = calculateAudioLevel(from: buffer)
            lastCalculationTime = currentTime
            
            // Update audio level on main thread
            DispatchQueue.main.async {
                self.audioLevel = level
                
                if self.state == .listening {
                    // print("Audio level: \(level) dB, buffer: \(self.isBufferFull ? "full" : "filling") (\(self.bufferIndex))")
                    
                    // Check if recording should be triggered
                    if level > self.silenceLevel {
                        print("=== TRIGGER: Audio level sufficient (\(level) dB) > silence threshold (\(self.silenceLevel) dB ===")
                        self.startRecording()
                    }
                } else if self.state == .recording {
                    // print("Recording - Time: \(self.recordingTime)s, Audio level: \(level) dB, Silence threshold: \(self.silenceLevel) dB")
                    
                    // Check for silence
                    if level < self.silenceLevel {
                        print("Silence detected: \(level) dB < \(self.silenceLevel) dB, starting silence timer...")
                        self.startSilenceTimer()
                    } else {
                        self.stopSilenceTimer()
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Buffer Management
    
    private func resetAudioBuffer() {
        // Calculate buffer size based on device sample rate (2 seconds of audio)
        let bufferSize: Int
        if let inputNode = inputNode {
            let sampleRate = inputNode.outputFormat(forBus: 0).sampleRate
            bufferSize = Int(sampleRate * 2.0) // 2 seconds
            // print("Setting buffer size to \(bufferSize) for sample rate \(sampleRate) Hz")
        } else {
            bufferSize = 32000 // fallback to 16kHz default
            // print("Using fallback buffer size \(bufferSize)")
        }
        
        audioBuffer = Array(repeating: 0, count: bufferSize)
        bufferIndex = 0
        isBufferFull = false
        // print("Audio buffer reset with size: \(bufferSize)")
    }
    
    private func fillAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Fill circular buffer with audio data
        for i in 0..<frameLength {
            audioBuffer[bufferIndex] = channelData[i]
            bufferIndex = (bufferIndex + 1) % audioBuffer.count
            
            if bufferIndex == 0 {
                isBufferFull = true
            }
        }
    }
    
    func getBufferData() -> [Float] {
        if !isBufferFull {
            // 缓冲区还没满，从0开始到bufferIndex
            return Array(audioBuffer[0..<bufferIndex])
        } else {
            // 缓冲区已满，从bufferIndex开始，环形读取一圈
            var result: [Float] = []
            
            // 从 bufferIndex（头部）开始，读取整个缓冲区
            for i in 0..<audioBuffer.count {
                let index = (bufferIndex + i) % audioBuffer.count
                result.append(audioBuffer[index])
            }
            
            return result
        }
    }
    
    // MARK: - Audio Level Calculation
    
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return -160.0 }
        let frameLength = Int(buffer.frameLength)
        
        // Calculate RMS (Root Mean Square)
        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 1e-10)) // Avoid log(0)
        
        return db
    }
    
    // MARK: - File Management
    
    private func createAudioFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        // Use device native format for recording
        guard let inputNode = inputNode else {
            print("ERROR: Input node not available for file creation")
            return
        }
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,  // Use device native sample rate
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        print("Creating audio file with settings: \(settings)")
        
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            currentFileURL = fileURL
            print("Audio file created: \(fileName) with format: \(inputFormat)")
        } catch {
            print("ERROR: Failed to create audio file: \(error)")
        }
    }
    
    // MARK: - Timer Management
    
    private func startRecordingTimer() {
        print("Starting recording timer...")
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingTime += 0.1
            
            // Check if maximum recording duration exceeded
            if self.recordingTime >= self.maxRecordingDuration {
                print("Recording stopped: Maximum duration reached (\(self.maxRecordingDuration)s)")
                self.stopRecording()
                return
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }
    
    private func startSilenceTimer() {
        if silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                print("Silence duration (\(self.silenceThreshold)s) reached, stopping recording...")
                self.stopRecording()
            }
        }
    }
    
    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: RecorderState) {
        let oldState = state
        state = newState
        
        print("State changed: \(oldState.description) → \(newState.description)")
        
        // Notify state change
        onStateChanged?(newState)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        print("Cleaning up AudioRecorder...")
        
        // Stop timers
        stopRecordingTimer()
        stopSilenceTimer()
        
        // Stop audio engine
        stopAudioEngine()
        
        // Close audio file
        audioFile = nil
        
        // Reset state
        updateState(.standby)
        
        print("AudioRecorder cleanup completed")
    }
}
