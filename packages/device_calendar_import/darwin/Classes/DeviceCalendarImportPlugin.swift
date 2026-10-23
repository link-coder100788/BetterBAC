// EventKit for BetterBAC, shared by iOS and macOS:
// - read-only Apple Calendar access for the calendar import
//   (the Rust side, api/device_calendar.rs, decides what to keep)
// - creating one reminder in Apple Reminders for the "most pressing task"
//   (api/tasks.rs decides what and when)

import EventKit

#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

public class DeviceCalendarImportPlugin: NSObject, FlutterPlugin {
  private var store = EKEventStore()

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "betterbac/device_calendar", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(DeviceCalendarImportPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasAccess":
      result(Self.hasAccess())
    case "requestAccess":
      requestAccess(result)
    case "listCalendars":
      guard Self.hasAccess() else { return result([]) }
      result(store.calendars(for: .event).map(Self.describe))
    case "events":
      guard Self.hasAccess(),
        let args = call.arguments as? [String: Any],
        let startMs = args["startMs"] as? Int,
        let endMs = args["endMs"] as? Int,
        let ids = args["calendarIds"] as? [String]
      else { return result([]) }
      let store = self.store
      // events(matching:) is synchronous and can be slow; keep it off the main thread.
      DispatchQueue.global(qos: .userInitiated).async {
        let events = Self.events(
          in: store,
          start: Date(timeIntervalSince1970: Double(startMs) / 1000),
          end: Date(timeIntervalSince1970: Double(endMs) / 1000),
          calendarIds: Set(ids))
        DispatchQueue.main.async { result(events) }
      }
    case "addReminder":
      addReminder(call.arguments, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Reminders

  /// Creates a reminder in the default Reminders list. Returns its id.
  private func addReminder(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let title = args["title"] as? String else {
      return result(FlutterError(code: "bad_args", message: "title required", details: nil))
    }
    withReminderAccess { granted in
      guard granted else {
        return result(FlutterError(code: "denied", message: "Reminders access denied", details: nil))
      }
      guard let list = self.store.defaultCalendarForNewReminders() else {
        return result(FlutterError(code: "no_list", message: "No default Reminders list", details: nil))
      }
      let reminder = EKReminder(eventStore: self.store)
      reminder.calendar = list
      reminder.title = title
      reminder.notes = args["notes"] as? String
      reminder.priority = Int(EKReminderPriority.high.rawValue)
      if let dueMs = args["dueMs"] as? Int {
        let due = Date(timeIntervalSince1970: Double(dueMs) / 1000)
        let allDay = args["allDay"] as? Bool ?? false
        let units: Set<Calendar.Component> =
          allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
        reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
      }
      if let remindMs = args["remindMs"] as? Int {
        reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: Double(remindMs) / 1000)))
      }
      do {
        try self.store.save(reminder, commit: true)
        result(reminder.calendarItemIdentifier)
      } catch {
        result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Calls `done` on the main thread with whether Reminders access is granted,
  /// asking first if needed.
  private func withReminderAccess(_ done: @escaping (Bool) -> Void) {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    let granted: Bool
    if #available(iOS 17.0, macOS 14.0, *) {
      granted = status == .fullAccess
    } else {
      granted = status == .authorized
    }
    if granted { return done(true) }
    let finish: (Bool, Error?) -> Void = { ok, _ in
      DispatchQueue.main.async {
        if ok { self.store = EKEventStore() }
        done(ok)
      }
    }
    if #available(iOS 17.0, macOS 14.0, *) {
      store.requestFullAccessToReminders(completion: finish)
    } else {
      store.requestAccess(to: .reminder, completion: finish)
    }
  }

  // MARK: Calendar import

  static func hasAccess() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, macOS 14.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func requestAccess(_ result: @escaping FlutterResult) {
    let done: (Bool, Error?) -> Void = { granted, _ in
      DispatchQueue.main.async {
        // A fresh store sees calendars that only became visible after access.
        if granted { self.store = EKEventStore() }
        result(granted)
      }
    }
    if #available(iOS 17.0, macOS 14.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  static func describe(_ cal: EKCalendar) -> [String: Any] {
    let holidays = cal.type == .subscription && cal.title.lowercased().contains("holiday")
    return [
      "id": cal.calendarIdentifier,
      "title": cal.title,
      "account": cal.source?.title ?? "",
      "color": argb(cal.cgColor),
      // Birthdays and subscribed holiday calendars start unticked.
      "suggested": cal.type != .birthday && !holidays,
    ]
  }

  static func events(in store: EKEventStore, start: Date, end: Date, calendarIds: Set<String>)
    -> [[String: Any]]
  {
    let calendars = store.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }
    guard !calendars.isEmpty, start < end else { return [] }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return store.events(matching: predicate).map { e in
      let ms = { (d: Date) in Int((d.timeIntervalSince1970 * 1000).rounded()) }
      let base = e.eventIdentifier ?? e.calendarItemIdentifier
      return [
        // One id per occurrence: recurring events share an identifier.
        "id": "\(base)@\(ms(e.startDate))",
        "calendarId": e.calendar.calendarIdentifier,
        "calendarTitle": e.calendar.title,
        "title": e.title ?? "",
        "notes": e.notes ?? "",
        "startMs": ms(e.startDate),
        "endMs": ms(e.endDate),
        "allDay": e.isAllDay,
      ]
    }
  }

  /// 0xAARRGGBB, for Flutter's `Color`.
  static func argb(_ color: CGColor?) -> Int {
    guard let color,
      let srgb = CGColorSpace(name: CGColorSpace.sRGB),
      let c = color.converted(to: srgb, intent: .defaultIntent, options: nil),
      let comps = c.components, comps.count >= 3
    else { return 0xFF1C_B0F6 }
    let byte = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
    let alpha = comps.count >= 4 ? comps[3] : 1
    return (byte(alpha) << 24) | (byte(comps[0]) << 16) | (byte(comps[1]) << 8) | byte(comps[2])
  }
}
