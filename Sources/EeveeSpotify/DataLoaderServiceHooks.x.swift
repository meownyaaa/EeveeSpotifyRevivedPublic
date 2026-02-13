import Foundation
import Orion

// Global variable for access token
public var spotifyAccessToken: String?

// Global counters for debugging 9.1.6
private var totalRequests = 0
private var lyricsRequests = 0
private var lastPopupTime: Date?
private var capturedURLs: [String] = []
private var isCapturingURLs = false

// Helper function to start capturing from other files
func DataLoaderServiceHooks_startCapturing() {
    isCapturingURLs = true
    capturedURLs.removeAll()
}

class SPTDataLoaderServiceHook: ClassHook<NSObject>, SpotifySessionDelegate {
    static let targetName = "SPTDataLoaderService"
    
    // orion:new
    func shouldModify(_ url: URL) -> Bool {
        let shouldPatchPremium = BasePremiumPatchingGroup.isActive
        let shouldReplaceLyrics = BaseLyricsGroup.isActive
        
        let isLyricsURL = url.isLyrics
        if isLyricsURL {
        }
        
        return (shouldReplaceLyrics && isLyricsURL)
            || (shouldPatchPremium && (url.isCustomize || url.isPremiumPlanRow || url.isPremiumBadge || url.isPlanOverview))
    }
    
    // orion:new
    func respondWithCustomData(_ data: Data, task: URLSessionDataTask, session: URLSession) {
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
    
    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        // Capture authorization token from any request
        if let request = task.currentRequest,
           let headers = request.allHTTPHeaderFields,
           let auth = headers["Authorization"] ?? headers["authorization"],
           auth.hasPrefix("Bearer ") {
            spotifyAccessToken = String(auth.dropFirst(7))
        }

        // Log request headers FIRST for ALL requests to lyrics endpoints
        if let url = task.currentRequest?.url, url.absoluteString.contains("lyrics") {
            if let request = task.currentRequest {
                if let headers = request.allHTTPHeaderFields {
                    for (key, value) in headers {
                        if key.lowercased().contains("auth") || key.lowercased().contains("token") || 
                           key.lowercased() == "user-agent" || key.lowercased() == "client-token" ||
                           key.lowercased() == "spotify-app-version" {
                        }
                    }
                } else {
                }
            } else {
            }
        }
        
        guard let url = task.currentRequest?.url else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        // Capture ALL URLs when debugging
        if isCapturingURLs && capturedURLs.count < 50 {
            capturedURLs.append(url.absoluteString)
            
            // After 15 requests, show popup with summary
            if capturedURLs.count == 15 {
                isCapturingURLs = false
                DispatchQueue.main.async {
                    let hasLyrics = capturedURLs.contains { $0.lowercased().contains("lyric") }
                    let hasColor = capturedURLs.contains { $0.contains("color") }
                    let hasSuno = capturedURLs.contains { $0.contains("suno") }
                    let hasApi = capturedURLs.contains { $0.contains("api.spotify") || $0.contains("spclient") }
                    
                    let message = """
                    Captured 15 requests:
                    
                    'lyric': \(hasLyrics ? "YES ✅" : "NO ❌")
                    'color': \(hasColor ? "YES" : "NO")
                    'suno': \(hasSuno ? "YES" : "NO")
                    Spotify API: \(hasApi ? "YES" : "NO")
                    
                    \(hasLyrics ? "Found lyrics URLs!" : "NO lyrics URLs.\n9.1.6 uses pre-loaded lyrics data.")
                    
                    All URLs logged to console.
                    """
                    
                    PopUpHelper.showPopUp(message: message, buttonText: "OK")
                }
            }
        }
        
        // C
        
        // Count all requests for debugging
        totalRequests += 1
        
        // Debug: Log all URLs that contain "lyric" (case insensitive)
        let urlString = url.absoluteString.lowercased()
        if urlString.contains("lyric") {
            lyricsRequests += 1
            
            // Show popup for first lyrics request
            if lyricsRequests == 1, let lastTime = lastPopupTime, Date().timeIntervalSince(lastTime) > 10 || lastPopupTime == nil {
                lastPopupTime = Date()
                DispatchQueue.main.async {
                    PopUpHelper.showPopUp(
                        message: "🎵 FOUND LYRICS REQUEST!\n\nURL: \(url.absoluteString)\n\n9.1.6 DOES make network requests for lyrics!",
                        buttonText: "OK"
                    )
                }
            }
        }
        
        // Also check for color-lyrics specifically
        if url.path.contains("color-lyrics") || url.path.contains("lyrics") {
        }
        
        guard error == nil, shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        
        // Log headers RIGHT HERE where we know code executes
        if url.isLyrics, let request = task.currentRequest {
            if let headers = request.allHTTPHeaderFields {
                for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                    let truncated = value.count > 80 ? "\(value.prefix(80))..." : value
                }
            }
        }
        
        guard let buffer = URLSessionHelper.shared.obtainData(for: url) else {
            return
        }
        
        
        do {
            if url.isLyrics {
                
                let originalLyrics = try? Lyrics(serializedBytes: buffer)
                
                // Try to fetch custom lyrics with a timeout
                let semaphore = DispatchSemaphore(value: 0)
                var customLyricsData: Data?
                var customLyricsError: Error?
                
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        customLyricsData = try getLyricsDataForCurrentTrack(
                            url.path,
                            originalLyrics: originalLyrics
                        )
                    } catch {
                        customLyricsError = error
                    }
                    semaphore.signal()
                }
                
                // Wait up to 5 seconds for custom lyrics (cached LRCLIB responses are instant)
                let timeout = DispatchTime.now() + .milliseconds(5000)
                let result = semaphore.wait(timeout: timeout)
                
                if result == .success, let data = customLyricsData {
                    respondWithCustomData(data, task: task, session: session)
                    
                    // Show popup indicating custom lyrics source - DISABLED FOR PRODUCTION
                    // DispatchQueue.main.async {
                    //     PopUpHelper.showPopUp(
                    //         message: "🎵 Using \(UserDefaults.lyricsSource.description) lyrics",
                    //         buttonText: "OK"
                    //     )
                    // }
                    
                    // Complete the request
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                } else {
                    if result == .timedOut {
                    } else {
                    }
                    respondWithCustomData(buffer, task: task, session: session)
                    
                    // Show popup indicating fallback to original - DISABLED FOR PRODUCTION
                    // DispatchQueue.main.async {
                    //     PopUpHelper.showPopUp(
                    //         message: result == .timedOut ? "⏱️ Using Spotify Original (timeout)" : "🎵 Using Spotify Original",
                    //         buttonText: "OK"
                    //     )
                    // }
                    
                    // Complete the request
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                }
                return
            }
            
            if url.isPremiumPlanRow {
                respondWithCustomData(
                    try getPremiumPlanRowData(
                        originalPremiumPlanRow: try PremiumPlanRow(serializedBytes: buffer)
                    ),
                    task: task,
                    session: session
                )
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            
            if url.isPremiumBadge {
                respondWithCustomData(try getPremiumPlanBadge(), task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            
            if url.isCustomize {
                var customizeMessage = try CustomizeMessage(serializedBytes: buffer)
                modifyRemoteConfiguration(&customizeMessage.response)
                respondWithCustomData(try customizeMessage.serializedData(), task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            
            if url.isPlanOverview {
                respondWithCustomData(try getPlanOverviewData(), task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
        }
        catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard
            let url = task.currentRequest?.url,
            url.isLyrics,
            response.statusCode != 200
        else {
            orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: handler)
            return
        }

        do {
            let data = try getLyricsDataForCurrentTrack(url.path)
            let okResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!
            
            orig.URLSession(session, dataTask: task, didReceiveResponse: okResponse, completionHandler: handler)
            respondWithCustomData(data, task: task, session: session)
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard let url = task.currentRequest?.url else {
            return
        }

        if shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: url)
            return
        }

        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
