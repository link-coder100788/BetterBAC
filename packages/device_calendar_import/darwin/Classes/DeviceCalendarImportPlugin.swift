// Read-only access to Apple Calendar (EventKit) for BetterBAC's calendar
// import. Shared by iOS and macOS. The Rust side (api/device_calendar.rs)
// decides what to keep; this file only reads.

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
    default:
      result(FlutterMethodNotImplemented)
    }
  }

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
