//
//  DepthServerClient.swift
//  SUPERWAAGE
//
//  Client for server-side AI denoising (optional enhancement)
//  Upload PLY point cloud → Server processes → Download denoised result
//

import Foundation

// MARK: - Configuration

struct DepthServerConfiguration: Sendable {
    let serverURL: URL
    let timeout: TimeInterval
    let uploadEndpoint: String
    let downloadEndpoint: String

    static let `default` = DepthServerConfiguration(
        serverURL: URL(string: "http://localhost:5000")!,
        timeout: 60.0,
        uploadEndpoint: "/denoise",
        downloadEndpoint: "/denoise"
    )
}

/// Client for server-side depth map denoising
@MainActor
class DepthServerClient {

    // MARK: - Properties

    private let configuration: DepthServerConfiguration
    private var currentTask: URLSessionDataTask?

    // MARK: - Initialization

    nonisolated init(configuration: DepthServerConfiguration) {
        self.configuration = configuration
    }

    nonisolated convenience init() {
        let defaultConfig = DepthServerConfiguration.default
        self.init(configuration: defaultConfig)
    }

    nonisolated convenience init(serverURL: URL) {
        let config = DepthServerConfiguration(
            serverURL: serverURL,
            timeout: 60.0,
            uploadEndpoint: "/denoise",
            downloadEndpoint: "/denoise"
        )
        self.init(configuration: config)
    }

    // MARK: - Server Health Check

    /// Check if server is available
    func checkServerAvailability() async -> Bool {
        let url = configuration.serverURL

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("⚠️ Server not available: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Upload & Denoise

    /// Upload point cloud for denoising
    /// - Parameters:
    ///   - plyData: PLY file data to denoise
    ///   - progress: Progress callback (0.0-1.0)
    /// - Returns: Denoised PLY data
    func denoise(
        plyData: Data,
        progress: @escaping (Double) -> Void
    ) async throws -> Data {
        let endpoint = configuration.serverURL.appendingPathComponent(configuration.uploadEndpoint)

        // Create multipart form data
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Add PLY file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"ply\"; filename=\"pointcloud.ply\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(plyData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Upload with progress tracking
        progress(0.1) // Starting

        let (data, response) = try await URLSession.shared.data(for: request)

        progress(0.9) // Processing complete

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DepthServerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw DepthServerError.serverError(statusCode: httpResponse.statusCode)
        }

        progress(1.0) // Done

        return data
    }

    // MARK: - Cancel

    /// Cancel current operation
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Errors

enum DepthServerError: Error {
    case invalidResponse
    case serverError(statusCode: Int)
    case noData
    case networkError(Error)

    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: HTTP \(code)"
        case .noData:
            return "No data received from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Usage Example

/*

 let client = DepthServerClient(serverURL: URL(string: "http://192.168.1.100:5000")!)

 // Check if server is available
 let isAvailable = await client.checkServerAvailability()

 if isAvailable {
     // Upload for denoising
     do {
         let plyData = try Data(contentsOf: plyFileURL)

         let denoisedData = try await client.denoise(plyData: plyData) { progress in
             print("Progress: \(Int(progress * 100))%")
         }

         // Save denoised result
         try denoisedData.write(to: denoisedFileURL)
         print("✅ Denoising complete!")

     } catch {
         print("❌ Denoising failed: \(error)")
     }
 }

 */
