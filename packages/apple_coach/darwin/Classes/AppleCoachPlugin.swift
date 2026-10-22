// Bridges BetterBAC's reflection coach to Apple Intelligence (the on-device
// Foundation Models framework, iOS / macOS 26+). The prompt is built in Rust;
// this file only checks availability and runs structured generation.

#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

public class AppleCoachPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "betterbac/apple_coach", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(AppleCoachPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(Self.status())

    case "generate":
      guard
        let args = call.arguments as? [String: Any],
        let instructions = args["instructions"] as? String,
        let prompt = args["prompt"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "instructions and prompt required", details: nil))
        return
      }
      #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        Task { @MainActor in
          do {
            result(try await Self.generate(instructions: instructions, prompt: prompt))
          } catch {
            result(FlutterError(code: "generation_failed", message: error.localizedDescription, details: nil))
          }
        }
        return
      }
      #endif
      result(FlutterError(code: "unsupported", message: "Apple Intelligence is not available", details: nil))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// "available", "unsupported", or "unavailable:<reason>".
  static func status() -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "available"
      case .unavailable(.deviceNotEligible):
        return "unavailable:deviceNotEligible"
      case .unavailable(.appleIntelligenceNotEnabled):
        return "unavailable:appleIntelligenceNotEnabled"
      case .unavailable(.modelNotReady):
        return "unavailable:modelNotReady"
      case .unavailable:
        return "unavailable:unknown"
      }
    }
    #endif
    return "unsupported"
  }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension AppleCoachPlugin {
  static func generate(instructions: String, prompt: String) async throws -> [String: Any] {
    let session = LanguageModelSession(instructions: instructions)
    let response = try await session.respond(
      to: prompt,
      generating: CoachFeedback.self,
      options: GenerationOptions(temperature: 0.6)
    )
    let feedback = response.content
    return [
      "headline": feedback.headline,
      "tips": feedback.tips.map { tip in
        [
          "kind": tip.kind == .praise ? "praise" : "suggestion",
          "title": tip.title,
          "body": tip.body,
        ]
      },
    ]
  }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachFeedback {
  @Guide(description: "One short, upbeat sentence summing up the reflection, at most 12 words.")
  var headline: String

  @Guide(description: "Two to four tips: first one or two praise tips, then the most useful suggestions.")
  var tips: [CoachTipOutput]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachTipOutput {
  @Guide(description: "praise if the student did this well, suggestion if it could improve")
  var kind: CoachTipKind

  @Guide(description: "A short title of 2 to 6 words")
  var title: String

  @Guide(description: "One or two friendly sentences addressed to the student as you")
  var body: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum CoachTipKind {
  case praise
  case suggestion
}
#endif
