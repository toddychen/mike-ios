//
//  RecordingFilesView.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import SwiftUI
import AVFoundation
import SwiftData

struct RecordingFilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioSegment.timestamp, order: .reverse) private var audioSegments: [AudioSegment]
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingId: PersistentIdentifier?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(audioSegments) { segment in
                    RecordingFileRow(
                        segment: segment,
                        isPlaying: currentlyPlayingId == segment.id,
                        onPlay: { playAudio(for: segment) },
                        onStop: { stopAudio() }
                    )
                }
                .onDelete(perform: deleteSegments)
            }
            .navigationTitle("Recording Files")
            .navigationBarTitleDisplayMode(.large)
                            .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Debug Files") {
                            debugAudioFiles()
                        }
                        .foregroundColor(.blue)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear All") {
                            clearAllRecordings()
                        }
                        .foregroundColor(.red)
                    }
                }
        }
        .onDisappear {
            stopAudio()
            cleanupAudioSession()
        }
        .onAppear {
            setupAudioSession()
        }
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            // Use .playback category for pure audio playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("RecordingFilesView: Audio session configured for .playback")
        } catch {
            print("RecordingFilesView: Failed to configure audio session: \(error)")
        }
    }
    
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("RecordingFilesView: Audio session deactivated")
        } catch {
            print("RecordingFilesView: Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Audio Playback
    
    private func playAudio(for segment: AudioSegment) {
        // Stop any currently playing audio
        stopAudio()
        
        // Get the audio file URL from the segment
        guard let audioURL = getAudioFileURL(for: segment) else {
            print("No audio file found for segment: \(segment.id)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = AudioPlayerDelegate(
                onFinish: { [self] in
                    DispatchQueue.main.async {
                        self.stopAudio()
                    }
                }
            )
            
            audioPlayer?.play()
            currentlyPlayingId = segment.id
            isPlaying = true
            
            // Start progress timer on main thread
            startPlaybackTimer()
            
            print("Playing audio file: \(audioURL.lastPathComponent)")
            print("Duration: \(audioPlayer?.duration ?? 0)s")
            
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingId = nil
        isPlaying = false
        playbackProgress = 0
        stopPlaybackTimer()
    }
    
    private func startPlaybackTimer() {
        // Ensure timer runs on main thread
        DispatchQueue.main.async {
            self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard let player = self.audioPlayer, player.isPlaying else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }
    
    private func stopPlaybackTimer() {
        DispatchQueue.main.async {
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
        }
    }
    
    private func getAudioFileURL(for segment: AudioSegment) -> URL? {
        print("=== Getting audio URL for segment: \(segment.id) ===")
        print("Segment timestamp: \(segment.timestamp)")
        print("Segment duration: \(segment.duration)s")
        
        // First try to use the saved audio file path
        if let audioPath = segment.audioFilePath {
            print("Saved audio path: \(audioPath)")
            
            // Try to create URL from the path
            var url: URL?
            
            // Check if it's already a valid file URL
            if audioPath.hasPrefix("file://") {
                url = URL(string: audioPath)
                print("Created URL from file:// path: \(url?.absoluteString ?? "nil")")
            } else {
                // Try to create a file URL from the path
                url = URL(fileURLWithPath: audioPath)
                print("Created URL from file path: \(url?.absoluteString ?? "nil")")
            }
            
            if let fileURL = url {
                let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
                print("File exists at path: \(fileExists)")
                print("Full file path: \(fileURL.path)")
                
                if fileExists {
                    // Get file attributes to verify it's the right file
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        let creationDate = attributes[.creationDate] as? Date
                        print("File size: \(fileSize) bytes")
                        print("File creation date: \(creationDate?.description ?? "unknown")")
                        
                        return fileURL
                    } catch {
                        print("Failed to get file attributes: \(error)")
                        return fileURL
                    }
                } else {
                    print("File does not exist at path: \(fileURL.path)")
                }
            } else {
                print("Failed to create URL from path: \(audioPath)")
            }
        } else {
            print("No audio file path saved for this segment")
        }
        
        print("=== No valid audio file found ===")
        return nil
    }
    
    // MARK: - Debug Methods
    
    private func debugAudioFiles() {
        print("=== DEBUG: Audio Files Status ===")
        
        // Check Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        print("Documents directory: \(documentsPath.path)")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            let audioFiles = files.filter { $0.pathExtension.lowercased().contains("m4a") || $0.pathExtension.lowercased().contains("wav") }
            
            print("Found \(audioFiles.count) audio files:")
            for (index, file) in audioFiles.enumerated() {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let creationDate = attributes[.creationDate] as? Date
                    let modificationDate = attributes[.modificationDate] as? Date
                    
                    print("  \(index + 1). \(file.lastPathComponent)")
                    print("     Path: \(file.path)")
                    print("     Size: \(fileSize) bytes")
                    print("     Created: \(creationDate?.description ?? "unknown")")
                    print("     Modified: \(modificationDate?.description ?? "unknown")")
                } catch {
                    print("  \(index + 1). \(file.lastPathComponent) - Error getting attributes: \(error)")
                }
            }
            
            if audioFiles.isEmpty {
                print("No audio files found in Documents directory")
            }
            
        } catch {
            print("Failed to list Documents directory: \(error)")
        }
        
        // Check saved segments
        print("\n=== DEBUG: Saved Segments ===")
        for (index, segment) in audioSegments.enumerated() {
            print("Segment \(index + 1):")
            print("  ID: \(segment.id)")
            print("  Timestamp: \(segment.timestamp)")
            print("  Duration: \(segment.duration)s")
            print("  Audio Path: \(segment.audioFilePath ?? "nil")")
            
            if let audioPath = segment.audioFilePath {
                if let url = URL(string: audioPath) {
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    print("  File exists: \(exists)")
                    print("  Full path: \(url.path)")
                } else {
                    print("  Invalid URL format")
                }
            }
        }
        
        print("=== DEBUG END ===")
    }
    
    // MARK: - Data Management
    
    private func deleteSegments(offsets: IndexSet) {
        print("=== Deleting selected segments ===")
        
        var deletedFilesCount = 0
        var deletedSegmentsCount = 0
        
        for index in offsets {
            let segment = audioSegments[index]
            
            // Delete the actual audio file if it exists
            if let audioPath = segment.audioFilePath {
                if deleteAudioFile(at: audioPath) {
                    deletedFilesCount += 1
                }
            }
            
            // Delete the database record
            modelContext.delete(segment)
            deletedSegmentsCount += 1
        }
        
        do {
            try modelContext.save()
            print("Successfully deleted \(deletedSegmentsCount) segments and \(deletedFilesCount) audio files")
        } catch {
            print("Failed to delete segments: \(error)")
        }
    }
    
    private func clearAllRecordings() {
        print("=== Starting comprehensive audio cleanup ===")
        
        // First, get all audio files in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var allAudioFiles: [URL] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            allAudioFiles = files.filter { $0.pathExtension.lowercased().contains("m4a") || $0.pathExtension.lowercased().contains("wav") }
            print("Found \(allAudioFiles.count) audio files to clean up")
        } catch {
            print("Failed to scan Documents directory: \(error)")
        }
        
        // Filter out files that might be in use (like temp files)
        let filesToDelete = allAudioFiles.filter { file in
            let fileName = file.lastPathComponent
            // Don't delete files that might be in use
            return !fileName.contains("temp_") && !fileName.contains("recording_")
        }
        
        print("Will delete \(filesToDelete.count) safe files (excluding potentially in-use files)")
        
        // Delete filtered audio files
        var deletedFilesCount = 0
        for audioFile in filesToDelete {
            do {
                try FileManager.default.removeItem(at: audioFile)
                deletedFilesCount += 1
                print("Deleted audio file: \(audioFile.lastPathComponent)")
            } catch {
                print("Failed to delete audio file \(audioFile.lastPathComponent): \(error)")
            }
        }
        
        // Delete database records
        var deletedSegmentsCount = 0
        for segment in audioSegments {
            // Delete the database record
            modelContext.delete(segment)
            deletedSegmentsCount += 1
        }
        
        // Save database changes
        do {
            try modelContext.save()
            print("Successfully cleared all recordings and audio files")
            print("Deleted \(deletedFilesCount) audio files and \(deletedSegmentsCount) database records")
        } catch {
            print("Failed to clear all recordings: \(error)")
        }
        
        print("=== Comprehensive audio cleanup completed ===")
    }
    
    private func deleteAudioFile(at path: String) -> Bool {
        // Convert string path to URL
        if let url = URL(string: path) {
            do {
                try FileManager.default.removeItem(at: url)
                print("Deleted audio file: \(url.lastPathComponent)")
                return true
            } catch {
                print("Failed to delete audio file at \(path): \(error)")
                return false
            }
        } else {
            print("Invalid audio file path: \(path)")
            return false
        }
    }
}

// MARK: - Recording File Row

struct RecordingFileRow: View {
    let segment: AudioSegment
    let isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.transcribedText.isEmpty ? "No transcription" : segment.transcribedText)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text("Duration: \(String(format: "%.1f", segment.duration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let audioPath = segment.audioFilePath {
                        Text("File: \(audioPath)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(nil) // 不限制行数，显示完整路径
                    }
                    
                    Text("Recorded: \(segment.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Play/Stop button
                Button(action: {
                    if isPlaying {
                        onStop()
                    } else {
                        onPlay()
                    }
                }) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(isPlaying ? .red : .blue)
                }
            }
            
            // Success indicator
            if segment.isSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Transcription successful")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Transcription failed")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Audio Player Delegate

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

#Preview {
    RecordingFilesView()
        .modelContainer(for: [AudioSegment.self, TextBlock.self], inMemory: true)
}
