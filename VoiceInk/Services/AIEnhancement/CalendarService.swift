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
    
    func getUpcomingEvents(limit: Int = 3, windowHours: Int = 2) async -> [CalendarEventContext] {
        guard isAuthorized else { return [] }
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: windowHours, to: now) ?? now
        
        // Predicate for events within window
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-900), end: endDate, calendars: nil) // Start 15 mins ago to catch current meetings
        
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        
        // Filter and map
        let contexts = events.prefix(limit).compactMap { event -> CalendarEventContext? in
            // Skip declined events
            // Note: Simplification for this context object
            
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
}
