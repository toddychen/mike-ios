//
//  ContentView.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TextBlock.lastUpdateTime, order: .reverse) private var textBlocks: [TextBlock]
    @StateObject private var continuousAudioManager = ContinuousAudioManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Recording control area
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Mike")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text(game.name)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(game.gameId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                    
                    // Recording button - moved above status labels
                    Button(action: {
                        continuousAudioManager.toggleContinuousRecording()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: continuousAudioManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                            Text(continuousAudioManager.isRecording ? "Stop Recording" : "Start Continuous Recording")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(continuousAudioManager.isRecording ? Color.red : Color.blue)
                        .cornerRadius(25)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .frame(maxWidth: .infinity) // Make button take full width
                                            .scaleEffect(continuousAudioManager.isRecording ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: continuousAudioManager.isRecording)
                    
                    // Recording status display - removed duplicate status label
                    VStack(spacing: 12) {
                        // Phase status
                        if continuousAudioManager.isRecording {
                            VStack(spacing: 8) {
                                // First row: Phase status (left aligned)
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mic.fill")
                                            .foregroundColor(continuousAudioManager.currentPhase == .recording ? .red : .blue)
                                            .scaleEffect(1.2)
                                        Text(continuousAudioManager.currentPhase.description)
                                            .font(.headline)
                                            .foregroundColor(continuousAudioManager.currentPhase == .recording ? .red : .blue)
                                    }
                                    Spacer()
                                }
                                
                                // Second row: Audio level (left) and recording time (right)
                                HStack {
                                    // Left: Audio level (always visible)
                                    HStack(spacing: 6) {
                                        Image(systemName: "waveform")
                                            .foregroundColor(.green)
                                        Text("\(String(format: "%.1f", continuousAudioManager.audioLevel)) dB")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    
                                    Spacer()
                                    
                                    // Right: Recording time (only when recording)
                                    if continuousAudioManager.currentPhase == .recording {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock")
                                                .foregroundColor(.orange)
                                            Text("\(String(format: "%.1f", continuousAudioManager.recordingTime))s")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                
                                // Third row: Async transcription status (left aligned, different color)
                                if continuousAudioManager.transcriptionStatus != .idle {
                                    HStack {
                                        HStack(spacing: 6) {
                                            Image(systemName: "text.bubble")
                                                .foregroundColor(.purple)
                                            Text("Async: \(continuousAudioManager.transcriptionStatus.description)")
                                                .font(.subheadline)
                                                .foregroundColor(.purple)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 16) // 增加左右边距
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity) // Make container take full width
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                // Control buttons row
                HStack {
                    // Recording Files button - 居左
                    NavigationLink(destination: RecordingFilesView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.title3)
                            Text("Recordings")
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    
                    Spacer()
                    
                    // New Session button - 居右
                    Button(action: {
                        startNewSession()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.title3)
                            Text("New Session")
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    .disabled(continuousAudioManager.isRecording)
                    .opacity(continuousAudioManager.isRecording ? 0.6 : 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Transcription results list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Text Blocks")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("Total: \(textBlocks.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if textBlocks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No text blocks")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Click the button above to start recording. The system will automatically detect silence and transcribe")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(textBlocks) { block in
                                    TextBlockView(block: block)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .onAppear {
            // Setup audio session for recording when entering main page
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
                print("ContentView: Audio session category set to .playAndRecord")
            } catch {
                print("ContentView: Failed to set audio session category: \(error)")
            }
            
            continuousAudioManager.setModelContext(modelContext)
        }
    }
    
    private func startNewSession() {
        // Clear all text blocks
        for block in textBlocks {
            modelContext.delete(block)
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to clear text blocks: \(error)")
        }
    }
}

struct TextBlockView: View {
    let block: TextBlock
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.startTime, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Duration: \(String(format: "%.1f", block.totalDuration))s • \(block.segmentCount) segments")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if block.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "clock.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            Text(block.content.isEmpty ? "No content" : block.content)
                .font(.body)
                .foregroundColor(block.content.isEmpty ? .secondary : .primary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    RecordingView(game: Game(gameId: "nfl.g.20250823025", name: "NFL Game 1", date: Date()))
        .modelContainer(for: [Game.self, AudioSegment.self, TextBlock.self], inMemory: true)
}
