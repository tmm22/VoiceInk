import Foundation
import EventKit
import OSLog

struct CalendarEventContext: Codable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let status: String // "Upcoming", "In Progress"
    
    var formattedDescription: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        
        let timeString = isAllDay ? "All Day" : "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        return "[\(status)] \(title) (\(timeString))"
    }
}

class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "CalendarService")
    
    // Check authorization status
    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }
    
    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            logger.error("Failed to request calendar access: \(error.localizedDescription)")
            return false
        }
    }
    
    func getUpcomingEvents(limit: Int = 3, windowHours: Int = 2, timeout: TimeInterval = 2.0) async -> [CalendarEventContext] {
        guard isAuthorized else { return [] }
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: windowHours, to: now) ?? now
        
        // Predicate for events within window (Start 15 mins ago to catch current meetings)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-900), end: endDate, calendars: nil)
        
        // Run in background with timeout
        return await withTaskGroup(of: [CalendarEventContext].self) { group in
            group.addTask {
                let task = Task.detached { [weak self, predicate] () -> [CalendarEventContext] in
                    guard let self = self else { return [] }
                    // Synchronous fetch
                    let events = self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
                    
                    // Filter and map
                    let contexts = events.prefix(limit).compactMap { event -> CalendarEventContext? in
                        let status: String
                        if event.startDate <= now && event.endDate >= now {
                            status = "In Progress"
                        } else {
                            status = "Upcoming"
                        }
                        
                        return CalendarEventContext(
                            title: event.title,
                            startDate: event.startDate,
                            endDate: event.endDate,
                            isAllDay: event.isAllDay,
                            status: status
                        )
                    }
                    return Array(contexts)
                }
                return await task.value
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return [] // Timeout returns empty list
            }
            
            if let result = await group.next(), !result.isEmpty {
                return result
            }
            return []
        }
    }
}
