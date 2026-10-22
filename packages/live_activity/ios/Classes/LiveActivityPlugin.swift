// Starts, updates and ends the "streak at risk" Live Activity. The content
// comes from Rust (api/reminders.rs); the UI is drawn by the BetterBACWidgets
// extension in ios/BetterBACWidgets.

import Flutter

#if canImport(ActivityKit)
import ActivityKit
#endif

public class LiveActivityPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "betterbac/live_activity", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LiveActivityPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(ActivityKit)
    if #available(iOS 16.2, *) {
      switch call.method {
      case "isSupported":
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      case "show":
        guard let args = call.arguments as? [String: Any],
          let state = StreakActivityAttributes.ContentState(args)
        else {
          result(FlutterError(code: "bad_args", message: "invalid activity content", details: nil))
          return
        }
        Task { @MainActor in
          do {
            try await Self.show(state)
            result(nil)
          } catch {
            result(FlutterError(code: "show_failed", message: error.localizedDescription, details: nil))
          }
        }
      case "end":
        Task { @MainActor in
          await Self.endAll()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
      return
    }
    #endif
    // Older iOS: nothing to show, but don't treat it as an error.
    result(call.method == "isSupported" ? false : nil)
  }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
extension LiveActivityPlugin {
  /// Updates the running activity, or starts one.
  static func show(_ state: StreakActivityAttributes.ContentState) async throws {
    let content = ActivityContent(state: state, staleDate: state.endsAt)
    let running = Activity<StreakActivityAttributes>.activities
    if let current = running.first {
      await current.update(content)
      for extra in running.dropFirst() {
        await extra.end(nil, dismissalPolicy: .immediate)
      }
    } else {
      _ = try Activity.request(
        attributes: StreakActivityAttributes(), content: content, pushType: nil)
    }
  }

  static func endAll() async {
    for activity in Activity<StreakActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}

/// Must match the copy in ios/BetterBACWidgets/StreakLiveActivity.swift
/// exactly (same name and fields), since ActivityKit matches them by type.
@available(iOS 16.1, *)
struct StreakActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var streak: Int
    var todayXp: Int
    var goalXp: Int
    var endsAt: Date
    var title: String
    var message: String
  }
}

@available(iOS 16.1, *)
extension StreakActivityAttributes.ContentState {
  init?(_ args: [String: Any]) {
    guard let streak = args["streak"] as? Int,
      let todayXp = args["todayXp"] as? Int,
      let goalXp = args["goalXp"] as? Int,
      let endsAtMs = args["endsAtMs"] as? Int,
      let title = args["title"] as? String,
      let message = args["message"] as? String
    else { return nil }
    self.init(
      streak: streak, todayXp: todayXp, goalXp: goalXp,
      endsAt: Date(timeIntervalSince1970: Double(endsAtMs) / 1000),
      title: title, message: message)
  }
}
#endif
