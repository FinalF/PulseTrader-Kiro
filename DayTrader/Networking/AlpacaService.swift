// AlpacaService.swift
// REST (historical bars) + WebSocket (real-time 1-min bars) via Alpaca Markets API
// Free tier uses IEX feed — real-time during market hours, no extra cost.

import Foundation
import Combine

final class AlpacaService: MarketDataService {

    private let apiKey: String
    private let apiSecret: String
    private let baseURL = Configuration.alpacaDataBaseURL

    // WebSocket state
    private var webSocketTask: URLSessionWebSocketTask?
    private var subjects: [String: PassthroughSubject<Quote, Never>] = [:]
    private var subscribedSymbols: Set<String> = []
    private var isAuthenticated = false
    private var pendingSubscriptions: [String] = []

    init(apiKey: String, apiSecret: String) {
        self.apiKey    = apiKey
        self.apiSecret = apiSecret
    }

    // MARK: - MarketDataService

    func fetchBars(symbol: String, limit: Int) async throws -> [Quote] {
        // Use last trading day (skip weekends) instead of always today
        let start = lastTradingDayStartISO()
        return try await fetchAlpacaBars(symbol: symbol, timeframe: "1Min",
                                          start: start, limit: limit)
    }

    func fetchBars(symbol: String, range: ChartRange) async throws -> [Quote] {
        let start = daysAgoISO(range.calendarDays)
        return try await fetchAlpacaBars(symbol: symbol,
                                          timeframe: range.alpacaTimeframe,
                                          start: start,
                                          limit: range.barLimit)
    }

    private func fetchAlpacaBars(symbol: String, timeframe: String,
                                   start: String, limit: Int) async throws -> [Quote] {
        var components = URLComponents(string: "\(baseURL)/v2/stocks/\(symbol)/bars")!
        components.queryItems = [
            URLQueryItem(name: "timeframe", value: timeframe),
            URLQueryItem(name: "start",     value: start),
            URLQueryItem(name: "limit",     value: "\(min(limit, 1000))"),
            URLQueryItem(name: "feed",      value: "iex"),
            URLQueryItem(name: "sort",      value: "asc"),
        ]
        guard let url = components.url else { throw AlpacaError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue(apiKey,    forHTTPHeaderField: "APCA-API-KEY-ID")
        request.addValue(apiSecret, forHTTPHeaderField: "APCA-API-SECRET-KEY")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        // Always print full raw response for debugging
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[Alpaca RAW] \(symbol) \(timeframe):\n\(raw)\n")

        do {
            let decoded = try JSONDecoder().decode(AlpacaBarsResponse.self, from: data)
            var quotes = decoded.bars.map { $0.toQuote(symbol: symbol) }
            for i in quotes.indices where i > 0 {
                quotes[i].previousClose = quotes[i - 1].close
            }
            print("[Alpaca OK] \(symbol): \(quotes.count) bars decoded")
            return quotes
        } catch {
            // Show the full decode error AND the raw JSON in the app
            print("[Alpaca DECODE FAIL] \(error)")
            throw AlpacaError.decodingFailed("[\(symbol)] \(error)\n\nRaw: \(raw.prefix(300))")
        }
    }

    func quotePublisher(for symbol: String) -> AnyPublisher<Quote, Never> {
        if let existing = subjects[symbol] {
            return existing.eraseToAnyPublisher()
        }
        let subject = PassthroughSubject<Quote, Never>()
        subjects[symbol] = subject

        if isAuthenticated {
            subscribeToSymbol(symbol)
        } else {
            pendingSubscriptions.append(symbol)
            if webSocketTask == nil { connectWebSocket() }
        }
        return subject.eraseToAnyPublisher()
    }

    // MARK: - WebSocket connection

    private func connectWebSocket() {
        guard let url = URL(string: Configuration.alpacaStreamURL) else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessages()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessages()   // keep listening
            case .failure:
                // Reconnect after 5s on failure
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.isAuthenticated = false
                    self.webSocketTask = nil
                    self.connectWebSocket()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        // Alpaca sends arrays of messages
        guard let array = try? JSONDecoder().decode([AlpacaWSMessage].self, from: data) else { return }

        for msg in array {
            switch msg.T {
            case "connected":
                authenticate()
            case "success" where msg.msg == "authenticated":
                isAuthenticated = true
                // Subscribe to all pending + already requested symbols
                let all = Array(subscribedSymbols) + pendingSubscriptions
                pendingSubscriptions.removeAll()
                all.forEach { subscribeToSymbol($0) }
            case "b":   // 1-min bar
                guard let symbol = msg.S,
                      let bar = msg.toQuote() else { break }
                DispatchQueue.main.async {
                    self.subjects[symbol]?.send(bar)
                }
            default:
                break
            }
        }
    }

    private func authenticate() {
        let auth = #"{"action":"auth","key":"\#(apiKey)","secret":"\#(apiSecret)"}"#
        webSocketTask?.send(.string(auth)) { _ in }
    }

    private func subscribeToSymbol(_ symbol: String) {
        subscribedSymbols.insert(symbol)
        let sub = #"{"action":"subscribe","bars":["\#(symbol)"]}"#
        webSocketTask?.send(.string(sub)) { _ in }
    }

    // MARK: - Helpers

    private static let easternTZ  = TimeZone(identifier: "America/New_York")!
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = easternTZ
        return f
    }()

    /// 09:30 ET of the most recent trading day (skips weekends)
    private func lastTradingDayStartISO() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.easternTZ
        var date = Date()
        // Walk backwards until we find a weekday
        for _ in 0..<7 {
            let weekday = cal.component(.weekday, from: date)
            if weekday >= 2 && weekday <= 6 { break }
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9; comps.minute = 30; comps.second = 0
        comps.timeZone = Self.easternTZ
        let start = cal.date(from: comps) ?? date
        return Self.isoFormatter.string(from: start)
    }

    private func sessionStartISO() -> String {
        lastTradingDayStartISO()
    }

    private func daysAgoISO(_ days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return Self.isoFormatter.string(from: date)
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:  throw AlpacaError.unauthorized
        case 429:       throw AlpacaError.rateLimited
        default:        throw AlpacaError.httpError(http.statusCode)
        }
    }
}

// MARK: - Error types

enum AlpacaError: LocalizedError {
    case invalidURL
    case unauthorized
    case rateLimited
    case httpError(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid Alpaca API URL"
        case .unauthorized:        return "Invalid Alpaca API key or secret"
        case .rateLimited:         return "Alpaca rate limit reached"
        case .httpError(let c):    return "Alpaca API error (HTTP \(c))"
        case .decodingFailed(let m): return "Alpaca data parse error: \(m)"
        }
    }
}

// MARK: - Decodable models

private struct AlpacaBarsResponse: Decodable {
    let bars: [AlpacaBar]
    let symbol: String?
    let next_page_token: String?   // snake_case matches Alpaca JSON
}

private struct AlpacaBar: Decodable {
    let t: String
    let o: Double
    let h: Double
    let l: Double
    let c: Double
    let v: Double
    let vw: Double?
    let n: Int?     // trade count (optional)

    func toQuote(symbol: String) -> Quote {
        let ts = parseDate(t) ?? Date()
        return Quote(symbol: symbol,
                     timestamp: ts,
                     open: o, high: h, low: l, close: c,
                     volume: Int(v),
                     previousClose: nil)
    }

    private func parseDate(_ str: String) -> Date? {
        // Try with fractional seconds first, then without
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]
        for f in formatters {
            if let d = f.date(from: str) { return d }
        }
        // Final fallback: strip sub-seconds manually
        let trimmed = str.replacingOccurrences(of: "\\.\\d+", with: "",
                                                options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

private struct AlpacaWSMessage: Decodable {
    let T: String           // message type
    let msg: String?        // "connected", "authenticated"
    let S: String?          // symbol (for bars)

    // Bar fields (present when T == "b")
    let o: Double?
    let h: Double?
    let l: Double?
    let c: Double?
    let v: Double?
    let t: String?          // timestamp

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func toQuote() -> Quote? {
        guard let symbol = S,
              let open = o, let high = h, let low = l, let close = c,
              let volume = v, let timestamp = t,
              let ts = Self.isoFormatter.date(from: timestamp)
        else { return nil }

        return Quote(symbol: symbol,
                     timestamp: ts,
                     open: open, high: high, low: low, close: close,
                     volume: Int(volume),
                     previousClose: nil)
    }
}
