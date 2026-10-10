import Foundation

// MARK: - Wire contract
//
// This file is the single source of truth for the shape of data exchanged between the
// macOS app and the audit backend (Python/FastAPI). `docs/contract.md` is the human-readable
// mirror with example JSON. Keep them in sync.
//
// Conventions
// - JSON keys are snake_case on the wire; Swift properties are camelCase. `ContractJSON.decoder`
//   handles the conversion, so never add `CodingKeys` here unless a key can't be derived.
// - Timestamps are ISO-8601 strings in UTC (`2026-10-10T19:02:11Z`).
// - Rates / scores are floats in [0, 1].
// - String enums that the backend may extend over time (failure modes) are modelled as
//   `RawRepresentable` structs so an unknown value still decodes.

/// Environment packaging format the audit understands.
public enum EnvFormat: String, Codable, Sendable, CaseIterable {
    case harbor, verifiers, openenv, custom

    public var displayName: String {
        switch self {
        case .harbor: "Harbor"
        case .verifiers: "Verifiers"
        case .openenv: "OpenEnv"
        case .custom: "Custom"
        }
    }
}

/// How the environment scores a rollout.
public enum RewardType: String, Codable, Sendable, CaseIterable {
    case programmatic
    case llmJudge = "llm_judge"
    case rubric
    case hybrid

    public var displayName: String {
        switch self {
        case .programmatic: "Programmatic"
        case .llmJudge: "LLM judge"
        case .rubric: "Rubric"
        case .hybrid: "Hybrid"
        }
    }
}

/// Summary of the sandbox the policy runs in while solving tasks.
public struct SandboxSummary: Codable, Hashable, Sendable {
    /// e.g. "docker · python:3.11-slim"
    public var runtime: String
    /// e.g. "egress allowed" / "none"
    public var network: String
    /// e.g. "/app rw · /tests ro"
    public var filesystem: String
    /// Tools the policy may call.
    public var tools: [String]
}

/// An RL training environment submitted for audit.
public struct AuditEnvironment: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var format: EnvFormat
    /// Local path or URL the environment was loaded from.
    public var source: String
    public var taskCount: Int
    public var rewardType: RewardType
    public var sandbox: SandboxSummary
    public var description: String?
}

// MARK: Lint

public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case info, warn, high

    private var rank: Int {
        switch self {
        case .info: 0
        case .warn: 1
        case .high: 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }

    public var displayName: String {
        switch self {
        case .info: "Info"
        case .warn: "Warning"
        case .high: "High"
        }
    }
}

/// Failure-mode taxonomy. Open set: the backend may add classes, unknown ones still decode.
public struct FailureMode: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public static let answerKeyReachable = FailureMode("answer_key_reachable")
    public static let graderDataReadable = FailureMode("grader_data_readable")
    public static let lengthExploit = FailureMode("length_exploit")
    public static let formatExploit = FailureMode("format_exploit")
    public static let judgeSycophancy = FailureMode("judge_sycophancy")
    public static let testOverfit = FailureMode("test_overfit")
    public static let toolEscape = FailureMode("tool_escape")
    public static let rewardSaturation = FailureMode("reward_saturation")
    public static let staleOracle = FailureMode("stale_oracle")
    public static let nondeterministicGrader = FailureMode("nondeterministic_grader")
    public static let earlyTermination = FailureMode("early_termination")
    public static let outputMimicry = FailureMode("output_mimicry")
    public static let graderInjection = FailureMode("grader_injection")
    public static let sandboxPersistence = FailureMode("sandbox_persistence")
    public static let specGaming = FailureMode("spec_gaming")

    public static let known: [FailureMode] = [
        .answerKeyReachable, .graderDataReadable, .lengthExploit, .formatExploit, .judgeSycophancy,
        .testOverfit, .toolEscape, .rewardSaturation, .staleOracle, .nondeterministicGrader,
        .earlyTermination, .outputMimicry, .graderInjection, .sandboxPersistence, .specGaming,
    ]

    /// Human-readable label, e.g. "Answer key reachable".
    public var displayName: String {
        let words = rawValue.split(separator: "_").map(String.init)
        guard let first = words.first else { return rawValue }
        return ([first.capitalized] + words.dropFirst().map { word in
            switch word {
            case "llm": "LLM"
            default: word
            }
        }).joined(separator: " ")
    }
}

/// Where a lint finding points to in the environment.
public struct FindingLocation: Codable, Hashable, Sendable {
    public var file: String?
    public var line: Int?
    public var taskId: String?

    public var displayString: String {
        var parts: [String] = []
        if let file {
            parts.append(line.map { "\(file):\($0)" } ?? file)
        }
        if let taskId { parts.append("task \(taskId)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// A static-analysis result on the environment, before any training happens.
public struct LintFinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var severity: Severity
    public var failureMode: FailureMode
    public var title: String
    public var location: FindingLocation
    public var explanation: String
    /// Short description of the fix. The full diff lives in `Patch`.
    public var suggestedPatch: String
}

// MARK: Run

public enum AuditPhase: String, Codable, Sendable, CaseIterable {
    case queued, linting, training, detecting, patching, verifying, done, failed

    public var displayName: String { rawValue.capitalized }
}

public struct RunConfig: Codable, Hashable, Sendable {
    /// Policy model used for adversarial training, e.g. "Qwen3-1.7B".
    public var model: String
    /// e.g. "GRPO"
    public var algorithm: String
    public var steps: Int
    public var seed: Int
    public var rolloutsPerStep: Int?
}

/// One end-to-end audit of an environment.
public struct AuditRun: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var envId: String
    public var phase: AuditPhase
    public var startedAt: Date
    public var endedAt: Date?
    public var config: RunConfig
}

// MARK: Training

/// One step of the training curve. The gap between `proxyReward` and `trueScore` is the story.
public struct TrainingPoint: Codable, Hashable, Sendable {
    public var step: Int
    /// What the environment's reward function paid out (mean over rollouts).
    public var proxyReward: Double
    /// Held-out / oracle measure of actual task quality.
    public var trueScore: Double
    /// KL divergence from the reference policy.
    public var kl: Double
    public var timestamp: Date

    public var gap: Double { proxyReward - trueScore }
}

/// The moment the detector decided proxy reward has decoupled from true quality.
public struct LiftoffEvent: Codable, Hashable, Sendable {
    public var step: Int
    public var confidence: Double
    public var failureMode: FailureMode
    /// Trajectory that triggered detection.
    public var trajectoryId: String
    public var summary: String
}

public struct RewardComponent: Codable, Hashable, Sendable {
    public var name: String
    public var value: Double
    public var weight: Double?
}

public struct RewardBreakdown: Codable, Hashable, Sendable {
    public var total: Double
    public var components: [RewardComponent]
}

/// A single rollout the policy produced during training.
public struct Trajectory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var step: Int
    public var taskId: String
    /// Truncated task prompt.
    public var prompt: String
    /// Full model output (tool calls + text).
    public var output: String
    public var reward: RewardBreakdown
    public var graderNotes: String
    public var isHack: Bool
    /// One human-readable line: what the policy did.
    public var summary: String
    /// Exact substring of `output` that constitutes the hack, for highlighting. Nil if clean.
    public var hackExcerpt: String?
}

// MARK: Patch

/// What the policy is and is not allowed to learn from. A first-class concept of the product.
public struct LearningScope: Codable, Hashable, Sendable {
    public var allow: [String]
    public var deny: [String]
}

public struct Patch: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var findingIds: [String]
    /// Unified diff against the environment root.
    public var diff: String
    public var rationale: String
    public var learningScope: LearningScope
}

// MARK: Verify

public struct RateSnapshot: Codable, Hashable, Sendable {
    public var passRate: Double
    public var hackRate: Double
}

public enum Verdict: String, Codable, Sendable {
    case pass, fail, inconclusive

    public var displayName: String {
        switch self {
        case .pass: "Hack closed · pass rate intact"
        case .fail: "Hack still present"
        case .inconclusive: "Inconclusive"
        }
    }
}

public struct VerifyResult: Codable, Hashable, Sendable {
    public var runId: String
    public var before: RateSnapshot
    public var after: RateSnapshot
    public var stepsRerun: Int
    public var verdict: Verdict
    public var summary: String
    /// Training curve of the re-run on the patched environment. Streamed separately over HTTP;
    /// bundled here in fixtures.
    public var training: [TrainingPoint]?
}

// MARK: Certificate

public struct FindingSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var failureMode: FailureMode
    public var severity: Severity
}

/// The artifact the customer files. Everything on it must be reproducible from the run.
public struct Certificate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var envId: String
    public var envName: String
    public var runId: String
    /// Content hash of the environment as submitted.
    public var envHash: String
    /// Content hash after the patch was applied. This is what the customer deploys.
    public var patchedEnvHash: String
    public var findingsClosed: [FindingSummary]
    public var before: RateSnapshot
    public var after: RateSnapshot
    public var config: RunConfig
    public var issuedAt: Date
    public var issuedBy: String
    public var signature: String
}

// MARK: - Streaming events

/// Events emitted while training (or re-verifying). Over HTTP these arrive as Server-Sent
/// Events where `event:` is the case name and `data:` is the JSON payload.
public enum TrainingEvent: Sendable, Hashable {
    case phase(AuditPhase)
    case point(TrainingPoint)
    case trajectory(Trajectory)
    case liftoff(LiftoffEvent)
    case verifyResult(VerifyResult)
    case completed
}

// MARK: - JSON coding

public enum ContractJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = iso8601Fraction.date(from: s) ?? iso8601.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad ISO-8601 date: \(s)"))
        }
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(iso8601.string(from: date))
        }
        return e
    }()

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let iso8601Fraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
