//
//  AudioRecorder.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import AVFoundation
import Combine

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    
    // Audio Recorder for actual recording
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    
    // Timers
    private var recordingTimer: Timer?
    private var silenceTimer: Timer?
    
    // History data handling
    private var tempHistoryFile: URL?
    
    // Configuration parameters
    let maxRecordingDuration: TimeInterval = 20.0 // Maximum recording duration 20 seconds
    let silenceThreshold: TimeInterval = 2.0 // Silence detection threshold 2 seconds
    let silenceLevel: Float = -45.0 // Silence level threshold in dB
    
    // Event callbacks
    var onRecordingFinished: ((URL, TimeInterval) -> Void)?
    
    override init() {
        super.init()
        // Audio session is now managed by ContinuousRecordingManager
    }
    
    // MARK: - Recording Management
    
    func startRecording(withHistoryData: [Float]) {
        guard !isRecording else { return }
        
        // 记录开始录音的时间
        let recordingStartTime = Date().timeIntervalSince1970
        print("🎙️ RECORDING STARTED at: \(recordingStartTime) (\(String(format: "%.3f", recordingStartTime)))")
        
        print("=== AudioRecorder: Starting recording with \(withHistoryData.count) samples of history ===")
        
        // Audio session is managed by ContinuousRecordingManager
        
        // Create recording file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        print("Recording file path: \(audioFilename)")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // Changed to 16kHz for Whisper compatibility
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        print("Audio settings: \(settings)")
        
        do {
            // First, create a temporary file with history data
            var tempHistoryFile: URL?
            if !withHistoryData.isEmpty {
                print("Creating temporary file with \(withHistoryData.count) samples of history data...")
                tempHistoryFile = createTempHistoryFile(withHistoryData: withHistoryData)
                print("History data written to temp file: \(tempHistoryFile?.lastPathComponent ?? "nil")")
            }
            
            // Create the main recorder
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            print("AudioRecorder created successfully")
            
            // Start recording
            let recordCallTime = Date().timeIntervalSince1970
            print("📞 CALLING record() at: \(recordCallTime) (\(String(format: "%.3f", recordCallTime)))")
            
            let recordingStarted = audioRecorder?.record() ?? false
            
            let recordReturnTime = Date().timeIntervalSince1970
            print("📞 record() RETURNED at: \(recordReturnTime) (\(String(format: "%.3f", recordReturnTime)))")
            print("Recording started: \(recordingStarted)")
            
            // 计算record()调用的延迟
            let recordCallDelay = recordReturnTime - recordCallTime
            print("⏱️ record() call delay: \(String(format: "%.3f", recordCallDelay))s")
            
            if recordingStarted {
                isRecording = true
                recordingTime = 0
                
                // Store temp history file for later merging
                self.tempHistoryFile = tempHistoryFile
                
                // Start recording timer
                startRecordingTimer()
                
                print("=== AudioRecorder: Recording started successfully ===")
            } else {
                print("ERROR: Failed to start recording")
            }
        } catch {
            print("ERROR: Failed to create AudioRecorder: \(error)")
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        print("=== AudioRecorder: Stopping recording ===")
        print("Recording duration: \(recordingTime)s")
        
        audioRecorder?.stop()
        isRecording = false
        
        // Get duration BEFORE stopping timer
        let duration = recordingTime
        print("Duration captured: \(duration)s")
        
        stopRecordingTimer()
        stopSilenceTimer()
        
        let recordingURL = getCurrentRecordingURL()
        
        print("Recording stopped after \(duration)s")
        print("Recording file: \(recordingURL?.absoluteString ?? "nil")")
        
        // Merge history data with recording if available
        if let historyFile = tempHistoryFile, let recordingURL = recordingURL {
            print("Merging history data with recording...")
            let mergedURL = mergeHistoryWithRecording(historyFile: historyFile, recordingFile: recordingURL)
            if let merged = mergedURL {
                print("Files merged successfully: \(merged.lastPathComponent)")
                
                // Clean up temp files
                cleanupTempFiles(historyFile: historyFile, recordingFile: recordingURL)
                
                // Call callback with merged file
                onRecordingFinished?(merged, duration)
                return merged
            }
        }
        
        // Call callback with original recording data
        if let url = recordingURL {
            print("Calling onRecordingFinished with duration: \(duration)s")
            onRecordingFinished?(url, duration)
        }
        
        return recordingURL
    }
    
    func getCurrentRecordingURL() -> URL? {
        return audioRecorder?.url
    }
    
    func cleanupRecorder() {
        // Don't set audioRecorder to nil immediately to avoid file deletion
        // Just stop recording if it's active
        if isRecording {
            audioRecorder?.stop()
            isRecording = false
        }
        
        // Reset timer
        recordingTime = 0
        stopRecordingTimer()
        stopSilenceTimer()
        
        print("AudioRecorder cleaned up (recorder reference preserved)")
    }
    

    private func mergeHistoryWithRecording(historyFile: URL, recordingFile: URL) -> URL? {
        // 目标输出路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mergedFileName = "merged_\(Date().timeIntervalSince1970).m4a"
        let mergedURL = documentsPath.appendingPathComponent(mergedFileName)

        print("Merging files:")
        print("  History: \(historyFile.lastPathComponent)")
        print("  Recording: \(recordingFile.lastPathComponent)")
        print("  Output: \(mergedFileName)")

        do {
            print("=== Starting file merge process ===")
            print("History file path: \(historyFile)")
            print("Recording file path: \(recordingFile)")
            print("Output file path: \(mergedURL)")
            
            // 读取两个音频文件
            print("Reading history file...")
            let historyAudioFile = try AVAudioFile(forReading: historyFile)
            print("History file read successfully")
            print("History file format: \(historyAudioFile.fileFormat)")
            print("History file processing format: \(historyAudioFile.processingFormat)")
            print("History file length: \(historyAudioFile.length) frames")
            
            print("Reading recording file...")
            let recordingAudioFile = try AVAudioFile(forReading: recordingFile)
            print("Recording file read successfully")
            print("Recording file format: \(recordingAudioFile.fileFormat)")
            print("Recording file processing format: \(recordingAudioFile.processingFormat)")
            print("Recording file length: \(recordingAudioFile.length) frames")

            // 使用录音文件的格式作为输出格式
            print("Creating output file with recording format settings...")
            let outputFile = try AVAudioFile(forWriting: mergedURL,
                                             settings: recordingAudioFile.fileFormat.settings)
            print("Output file created successfully")

            // 工具函数：把一个音频文件写入 output
            func appendFile(_ sourceFile: AVAudioFile, to outputFile: AVAudioFile) throws {
                let format = sourceFile.processingFormat
                print("Appending file with format: \(format)")
                print("Format sample rate: \(format.sampleRate)")
                print("Format channels: \(format.channelCount)")
                
                let frameCapacity: AVAudioFrameCount = 1024
                print("Creating buffer with frame capacity: \(frameCapacity)")

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                    print("❌ Failed to create buffer for format: \(format)")
                    throw NSError(domain: "MergeError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
                }
                print("✅ Buffer created successfully")

                var totalFramesWritten = 0
                var iterationCount = 0
                print("Starting file append process...")
                print("Source file length: \(sourceFile.length) frames")
                print("Source file current position: \(sourceFile.framePosition) frames")
                
                while sourceFile.framePosition < sourceFile.length {
                    iterationCount += 1
                    print("=== Iteration \(iterationCount) ===")
                    print("Current position: \(sourceFile.framePosition) / \(sourceFile.length)")
                    
                    let remainingFrames = sourceFile.length - sourceFile.framePosition
                    print("Remaining frames to read: \(remainingFrames)")
                    
                    print("Reading from source file...")
                    try sourceFile.read(into: buffer)
                    print("Read result: buffer.frameLength = \(buffer.frameLength)")
                    
                    print("Writing \(buffer.frameLength) frames to output...")
                    try outputFile.write(from: buffer)
                    print("Write successful")
                    
                    totalFramesWritten += Int(buffer.frameLength)
                    print("Total frames written so far: \(totalFramesWritten)")
                    print("---")
                }
                
                print("File append completed. Final position: \(sourceFile.framePosition) / \(sourceFile.length)")
                print("File appended successfully, total frames: \(totalFramesWritten)")
            }

            // 先写入历史文件
            print("=== Appending history file ===")
            try appendFile(historyAudioFile, to: outputFile)
            print("✅ History file appended successfully")

            // 再写入录音文件
            print("=== Appending recording file ===")
            try appendFile(recordingAudioFile, to: outputFile)
            print("✅ Recording file appended successfully")

            print("🎉 Files merged successfully at \(mergedURL)")
            return mergedURL

        } catch {
            print("❌ Failed to merge files: \(error)")
            print("Error domain: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("NSError domain: \(nsError.domain)")
                print("NSError code: \(nsError.code)")
                print("NSError userInfo: \(nsError.userInfo)")
            }
            return nil
        }
    }
    

    
    private func cleanupTempFiles(historyFile: URL, recordingFile: URL) {
        // Clean up temporary files
        do {
            if FileManager.default.fileExists(atPath: historyFile.path) {
                try FileManager.default.removeItem(at: historyFile)
                print("History temp file cleaned up: \(historyFile.lastPathComponent)")
            }
        } catch {
            print("Failed to cleanup history temp file: \(error)")
        }
    }
    
    private func createTempHistoryFile(withHistoryData: [Float]) -> URL? {
        // Create a temporary file with history data using the same format as recording
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempFileName = "temp_history_\(Date().timeIntervalSince1970).m4a"
        let tempFileURL = documentsPath.appendingPathComponent(tempFileName)
        
        // Use the same format as recording (AAC) for better compatibility
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // Changed to 16kHz for Whisper compatibility
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            // Create audio file with recording format
            let audioFile = try AVAudioFile(forWriting: tempFileURL, settings: settings)
            
            // Convert Float array to PCM buffer
            guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
                print("Failed to create audio format")
                return nil
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(withHistoryData.count)) else {
                print("Failed to create PCM buffer")
                return nil
            }
            
            // Fill buffer with history data
            for i in 0..<withHistoryData.count {
                buffer.floatChannelData?[0][i] = withHistoryData[i]
            }
            buffer.frameLength = AVAudioFrameCount(withHistoryData.count)
            
            // Write to file
            try audioFile.write(from: buffer)
            print("History data written to temp file: \(tempFileURL.lastPathComponent)")
            print("History file size: \(withHistoryData.count * 4) bytes")
            print("History file format: \(settings)")
            return tempFileURL
        } catch {
            print("Failed to create temp history file: \(error)")
            return nil
        }
    }
    
    private func writeAudioDataToFile(_ audioData: [Float], fileURL: URL) -> Bool {
        // Create WAV format file
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
            print("Failed to create audio format")
            return false
        }
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: audioFormat.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(audioData.count)) else {
                print("Failed to create PCM buffer")
                return false
            }
            
            // Fill buffer with audio data
            for i in 0..<audioData.count {
                buffer.floatChannelData?[0][i] = audioData[i]
            }
            buffer.frameLength = AVAudioFrameCount(audioData.count)
            
            // Write to file
            try audioFile.write(from: buffer)
            print("Audio data written to file: \(audioData.count) samples")
            return true
        } catch {
            print("Failed to write audio data to file: \(error)")
            return false
        }
    }
    
    
    // MARK: - Recording Timer
    
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
            
            // Check audio level for silence detection
            self.audioRecorder?.updateMeters()
            let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160.0
            
            // Log audio level every second for debugging
            if Int(self.recordingTime * 10) % 10 == 0 {
                print("Recording - Time: \(self.recordingTime)s, Audio level: \(level) dB, Silence threshold: \(self.silenceLevel) dB")
            }
            
            // Check for silence
            if level < self.silenceLevel {
                print("Silence detected: \(level) dB < \(self.silenceLevel) dB, starting silence timer...")
                self.startSilenceTimer()
            } else {
                self.stopSilenceTimer()
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }
    
    // MARK: - Silence Detection
    
    private func startSilenceTimer() {
        if silenceTimer == nil {
            print("Starting silence timer for \(silenceThreshold)s...")
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("Silence timer triggered after \(self.silenceThreshold)s of silence")
                print("Recording stopped: Silence detected after \(self.recordingTime)s")
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
    }
    
    private func stopSilenceTimer() {
        if silenceTimer != nil {
            print("Stopping silence timer (sound detected)")
            silenceTimer?.invalidate()
            silenceTimer = nil
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("AudioRecorder: Recording finished, success: \(flag)")
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("AudioRecorder: Recording encoding error: \(error)")
        }
    }
}
