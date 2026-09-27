// SignalsViewModel.swift
import Foundation
import Combine
import UserNotifications

enum SignalFilterDirection: String, CaseIterable {
    case all  = "All"
    case buy  = "Buy"
    case sell = "Sell"
}

enum SignalFilterTier: String, CaseIterable {
    case all    = "All"
    case high   = "High"
    case medium = "Medium"
}

@MainActor
final class SignalsViewModel: ObservableObject {

    @Published var allSignals: [TradeSignal] = []
    @Published var filterSymbol: String = ""
    @Published var filterDirection: SignalFilterDirection = .all
    @Published var filterTier: SignalFilterTier = .all

    var filteredSignals: [TradeSignal] {
        allSignals
            .filter { signal in
                (filterSymbol.isEmpty || signal.symbol == filterSymbol) &&
                (filterDirection == .all || signal.direction.rawValue == filterDirection.rawValue) &&
                (filterTier == .all || signal.tier.rawValue == filterTier.rawValue)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Append new signal (called by WatchlistViewModel / ChartViewModel)

    func append(_ signal: TradeSignal) {
        allSignals.insert(signal, at: 0)
        scheduleNotificationIfNeeded(signal)
    }

    func clear() { allSignals.removeAll() }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func scheduleNotificationIfNeeded(_ signal: TradeSignal) {
        guard signal.confidence >= 0.80 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(signal.direction.emoji) \(signal.symbol) — \(signal.direction.rawValue) Signal"
        content.body  = "Confidence \(signal.displayConfidence) · Entry $\(String(format: "%.2f", signal.entryPrice))"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: signal.id.uuidString,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
