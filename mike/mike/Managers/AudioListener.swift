//
//  AudioListener.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation
import Combine

class AudioListener: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var audioLevel: Float = 0.0
    
    // Audio Engine for listening
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // Audio level detection control
    private var lastCalculationTime: TimeInterval = 0
    private let calculationInterval: TimeInterval = 0.02 // 0.02 second interval (20ms for faster response)
    
    // Pre-recording buffer - 2 seconds of audio data
    private var audioBuffer: [Float] = Array(repeating: 0, count: 32000) // 16kHz, 2 seconds
    private var bufferIndex = 0
    private var isBufferFull = false
    
    // Configuration parameters
    let silenceLevel: Float = -45.0 // Silence level threshold in dB
    

    
    // Event callbacks - Listener 只负责触发事件，不管理业务状态
    var onRecordingTriggered: (([Float]) -> Void)?
    
    override init() {
        super.init()
        // Audio session is now managed by ContinuousRecordingManager
    }
    
    // MARK: - Public Interface
    
    func startListening() {
        guard !isListening else { return }
        
        print("=== AudioListener: Starting audio listening ===")
        print("Detection interval: \(calculationInterval * 1000)ms")
        print("Silence level threshold: \(silenceLevel) dB")
        
        // Audio session is managed by ContinuousRecordingManager
        
        // Ensure clean state before starting
        if audioEngine != nil || inputNode != nil {
            print("Warning: Audio engine not properly cleaned up, forcing cleanup...")
            stopAudioEngine()
        }
        
        // Reset audio buffer
        resetAudioBuffer()
        
        // Setup and start audio engine
        setupAudioEngine()
        
        if audioEngine != nil && inputNode != nil {
            isListening = true
            print("Audio listening started successfully")
        } else {
            print("ERROR: Failed to start audio listening")
            isListening = false
        }
    }
    
    func stopListening() {
        guard isListening else { return }
        
        isListening = false
        print("=== AudioListener: Stopping audio listening ===")
        
        // Stop audio engine
        stopAudioEngine()
        
        // Audio session cleanup is managed by ContinuousRecordingManager
    }
    
    // MARK: - Audio Engine Management
    
    private func setupAudioEngine() {
        print("Setting up audio engine...")
        
        // Create new audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("ERROR: Failed to create audio engine")
            return
        }
        
        // Get input node
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("ERROR: Failed to get input node")
            return
        }
        
        print("Audio engine and input node created successfully")
        
        // Get the actual input format from the input node
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Using input node's actual format: \(inputFormat)")
        
        // Verify the format properties
        print("Input format validation:")
        print("  Sample rate: \(inputFormat.sampleRate) Hz")
        print("  Channel count: \(inputFormat.channelCount)")
        print("  Format ID: \(inputFormat.streamDescription.pointee.mFormatID)")
        print("  Format flags: \(inputFormat.streamDescription.pointee.mFormatFlags)")
        
        // Check if format has valid values
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("ERROR: Invalid audio format values - Sample rate: \(inputFormat.sampleRate), Channels: \(inputFormat.channelCount)")
            return
        }
        
        // Install tap on input node to monitor audio levels
        do {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }
            print("Audio tap installed successfully")
        } catch {
            print("ERROR: Failed to install audio tap: \(error)")
            return
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            print("ERROR: Failed to start audio engine: \(error)")
            print("Error details: \(error.localizedDescription)")
            return
        }
        
        print("Audio engine setup completed successfully")
    }
    
    private func stopAudioEngine() {
        print("Stopping audio engine...")
        
        // Remove tap first
        if let inputNode = inputNode {
            inputNode.removeTap(onBus: 0)
            print("Audio tap removed")
        }
        
        // Stop engine
        if let audioEngine = audioEngine {
            audioEngine.stop()
            print("Audio engine stopped")
        }
        
        // Clear references
        audioEngine = nil
        inputNode = nil
        audioLevel = 0.0
        
        // Force audio session reset
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session forcefully deactivated")
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        print("Audio engine cleanup completed")
    }
    
    // MARK: - Audio Buffer Management
    
    private func resetAudioBuffer() {
        audioBuffer = Array(repeating: 0, count: 32000)  // Changed to 16kHz, 2 seconds buffer size
        bufferIndex = 0
        isBufferFull = false
        print("Audio buffer reset")
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
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Always fill audio buffer
        fillAudioBuffer(buffer)
        
        // 2. Check audio level at specified intervals
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastCalculationTime >= calculationInterval {
            let level = calculateAudioLevel(from: buffer)
            lastCalculationTime = currentTime
            
            // Update audio level on main thread
            DispatchQueue.main.async {
                self.audioLevel = level
                
                print("Audio level: \(level) dB, buffer: \(self.isBufferFull ? "full" : "filling") (\(self.bufferIndex))")
                
                // Check if recording should be triggered
                if self.isListening && level > self.silenceLevel {
                    print("=== TRIGGER: Audio level sufficient (\(level) dB) > silence threshold (\(self.silenceLevel) dB ===")
                    self.triggerRecording()
                } else if self.isListening {
                    print("=== NO TRIGGER: Audio level (\(level) dB) <= silence threshold (\(self.silenceLevel) dB ===")
                }
            }
        }
    }
    
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
    

    
    // MARK: - Recording Trigger
    
    private func triggerRecording() {
        guard isListening else { return }
        
        let triggerStartTime = Date().timeIntervalSince1970
        print("🚀 TRIGGER RECORDING STARTED at: \(triggerStartTime) (\(String(format: "%.3f", triggerStartTime)))")
        print("=== AudioListener: Triggering recording, stopping listening ===")
        
        // 1. 立即停止自己的监听工作
        stopListening()
        
        // 2. 获取当前缓冲区数据（使用正确的环形读取逻辑）
        let bufferData = getBufferData()
        print("AudioListener: Buffer data ready, \(bufferData.count) samples")
        print("AudioListener: Buffer status - isFull: \(isBufferFull), index: \(bufferIndex)")
        
        // 3. 通知 Manager 可以开始录音了
        onRecordingTriggered?(bufferData)
        
        // 4. 重置缓冲区，准备下次使用
        resetAudioBuffer()
    }
    
    // MARK: - Buffer Status
    
    func getBufferStatus() -> (isFull: Bool, sampleCount: Int, index: Int) {
        return (isBufferFull, audioBuffer.count, bufferIndex)
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
}
