// The "streak at risk" Live Activity: lock screen banner and Dynamic Island.
// Started, updated and ended by packages/live_activity; content from Rust.
// On macOS 26+ it also appears in the Mac's menu bar via iPhone Mirroring.

import ActivityKit
import SwiftUI
import WidgetKit

/// Must match the copy in packages/live_activity/ios/Classes/LiveActivityPlugin.swift.
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

private let flameOrange = Color(red: 1.0, green: 0.588, blue: 0.0)  // #FF9600
private let goalGreen = Color(red: 0.345, green: 0.8, blue: 0.008)  // #58CC02

extension StreakActivityAttributes.ContentState {
  /// Counts down to midnight; never an invalid (reversed) range.
  var countdown: ClosedRange<Date> {
    let now = Date()
    return now...max(now, endsAt)
  }

  var goalProgress: Double {
    guard goalXp > 0 else { return 0 }
    return min(Double(todayXp) / Double(goalXp), 1)
  }
}

struct StreakLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StreakActivityAttributes.self) { context in
      StreakLockScreenView(state: context.state)
        .activitySystemActionForegroundColor(flameOrange)
    } dynamicIsland: { context in
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("\(state.streak)", systemImage: "flame.fill")
            .font(.system(.title2, design: .rounded).weight(.heavy))
            .foregroundStyle(flameOrange)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(timerInterval: state.countdown, countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(flameOrange)
            .frame(maxWidth: 96)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(state.message)
              .font(.system(.subheadline, design: .rounded).weight(.semibold))
            ProgressView(value: state.goalProgress)
              .tint(goalGreen)
          }
        }
      } compactLeading: {
        HStack(spacing: 2) {
          Image(systemName: "flame.fill")
          Text("\(state.streak)").fontWeight(.heavy)
        }
        .foregroundStyle(flameOrange)
      } compactTrailing: {
        Text(timerInterval: state.countdown, countsDown: true)
          .monospacedDigit()
          .frame(maxWidth: 56)
          .foregroundStyle(flameOrange)
      } minimal: {
        Image(systemName: "flame.fill")
          .foregroundStyle(flameOrange)
      }
      .keylineTint(flameOrange)
    }
  }
}

struct StreakLockScreenView: View {
  let state: StreakActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(flameOrange)
          .frame(width: 56, height: 56)
        Image(systemName: "flame.fill")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(.white)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(state.title)
          .font(.system(.headline, design: .rounded).weight(.heavy))
        HStack(spacing: 4) {
          Text("Ends in")
          Text(timerInterval: state.countdown, countsDown: true)
            .monospacedDigit()
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundStyle(flameOrange)
        ProgressView(value: state.goalProgress) {
          Text("\(state.todayXp) / \(state.goalXp) XP today")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .tint(goalGreen)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
  }
}
