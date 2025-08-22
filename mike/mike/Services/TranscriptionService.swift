//
//  TranscriptionService.swift
//  mike
//
//  Created by Toddy on 8/19/25.
//

import Foundation
import Combine

class TranscriptionService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastError: String?
    
    // Please replace with your web server URL
    private let baseURL = "http://192.168.86.32:3000" // or your actual server address
    
    func transcribeAudio(audioURL: URL) async throws -> String {
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/api/audio/transcribe")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        print("Sending transcription request to: \(request.url?.absoluteString ?? "unknown")")
        
        var body = Data()
        
        // Add audio file
        let audioData = try Data(contentsOf: audioURL)
        print("Audio file size: \(audioData.count) bytes")
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio_file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        print("Request body size: \(body.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid HTTP response type")
            throw TranscriptionError.invalidResponse
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        print("Response Headers: \(httpResponse.allHeaderFields)")
        
        guard httpResponse.statusCode == 200 else {
            print("Server error with status code: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error response body: \(errorData)")
            }
            throw TranscriptionError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Parse JSON response
        do {
            // Log the raw JSON response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Server JSON Response: \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(TranscriptionResponse.self, from: data)
            
            guard result.success else {
                throw TranscriptionError.serverError(statusCode: 400)
            }
            
            return result.transcription
        } catch {
            print("JSON parsing error: \(error)")
            throw TranscriptionError.invalidData
        }
    }
}

// MARK: - Data Models

struct TranscriptionResponse: Codable {
    let success: Bool
    let transcription: String
    let language: String
    let fileSize: Int
    let model: String
    let method: String
    let performanceMetrics: [String: Double]
    
    enum CodingKeys: String, CodingKey {
        case success, transcription, language
        case fileSize = "file_size"
        case model, method
        case performanceMetrics = "performance_metrics"
    }
}

// MARK: - Error Handling

enum TranscriptionError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case invalidData
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .invalidData:
            return "Invalid data format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
