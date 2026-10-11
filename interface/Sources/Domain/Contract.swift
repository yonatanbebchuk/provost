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

/// The six parts every environment must specify (from the structural comparison of 30 public
/// environments in `auto_RL_builder/environment_comparison.md`). A patch names which parts it changes.
public enum EnvironmentPart: String, Codable, Sendable, CaseIterable, Identifiable {
    case objective
    case initialState = "initial_state"
    case observations
    case actions
    case evaluation
    case episode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .objective: "Objective"
        case .initialState: "Initial state"
        case .observations: "Observation space"
        case .actions: "Action space"
        case .evaluation: "Reward"
        case .episode: "Episode"
        }
    }

    /// One line explaining the part to someone new to RL environments.
    public var blurb: String {
        switch self {
        case .objective: "What done means, and what must stay true."
        case .initialState: "How an attempt begins and what it starts with."
        case .observations: "What the policy observes, and what stays with the grader."
        case .actions: "What the policy may do, and how each action is interpreted."
        case .evaluation: "The reward function: how a rollout is scored and what the score means."
        case .episode: "When an attempt ends and how the next one starts clean."
        }
    }

    public var systemImage: String {
        switch self {
        case .objective: "target"
        case .initialState: "square.stack.3d.up"
        case .observations: "eye"
        case .actions: "hand.tap"
        case .evaluation: "checkmark.seal"
        case .episode: "arrow.counterclockwise"
        }
    }
}

public struct KeyValue: Codable, Hashable, Sendable {
    public var key: String
    public var value: String
}

public struct ObjectiveSpec: Codable, Hashable, Sendable {
    /// Intended outcome in one or two sentences.
    public var summary: String
    /// Protected conditions: things that must remain true, including legitimate refusals.
    public var constraints: [String]
}

public struct InitialStateSpec: Codable, Hashable, Sendable {
    public var summary: String
    public var items: [KeyValue]
}

/// The visibility boundary. Evaluator internals never appear in `visible`.
public struct ObservationSpec: Codable, Hashable, Sendable {
    public var visible: [String]
    public var hidden: [String]
}

public struct ActionContract: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var description: String
    public var arguments: [String]?
}

public struct EvaluationSpec: Codable, Hashable, Sendable {
    public var summary: String
    public var components: [String]
    /// Independent outcome check used by the audit, if the environment has one.
    public var audit: String?
    /// Source of the reward function, when the backend can show it.
    public var code: String?
    /// File the reward function lives in, for the code header.
    public var codePath: String?

    public init(summary: String, components: [String], audit: String? = nil, code: String? = nil, codePath: String? = nil) {
        self.summary = summary
        self.components = components
        self.audit = audit
        self.code = code
        self.codePath = codePath
    }
}

public struct EpisodeSpec: Codable, Hashable, Sendable {
    public var termination: String
    public var maxSteps: Int?
    public var reset: String
}

public enum ProvenanceOrigin: String, Codable, Sendable {
    case thirdParty = "third_party"
    case supported
    case designChoice = "design_choice"
    case synthetic

    public var displayName: String {
        switch self {
        case .thirdParty: "Third-party environment"
        case .supported: "Source-supported"
        case .designChoice: "Design choice"
        case .synthetic: "Synthetic"
        }
    }
}

public struct ProvenanceSpec: Codable, Hashable, Sendable {
    public var origin: ProvenanceOrigin
    public var evidence: [String]
    public var license: String?
}

/// One task instance the policy will be trained on: the input it receives.
public struct SampleInput: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var prompt: String
    public var source: String?
}

/// Full structural description of an environment. Optional on the wire so a backend that only
/// knows the packaging can still register an environment; the app shows gaps honestly.
public struct EnvironmentSpec: Codable, Hashable, Sendable {
    /// A few task inputs, so a reader sees what the policy is trained on before anything else.
    public var samples: [SampleInput]?
    public var objective: ObjectiveSpec
    public var initialState: InitialStateSpec
    public var observations: ObservationSpec
    public var actions: [ActionContract]
    public var evaluation: EvaluationSpec
    public var episode: EpisodeSpec
    public var provenance: ProvenanceSpec
}

/// An RL training environment submitted for audit. Environments are the app's projects.
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
    public var spec: EnvironmentSpec?
    /// The certificate from the last time this environment was signed, if any. The app marks it
    /// stale when the auditor has moved on or the environment changed.
    public var lastCertificate: Certificate?
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
    // From Matt's red-team harness (auto_RL_builder/redteam_testing): grader gaps in workflow environments.
    public static let omittedEpistemicRequirement = FailureMode("omitted_epistemic_requirement")
    public static let ungradedExternality = FailureMode("ungraded_externality")
    public static let unenforcedRequiredApproval = FailureMode("unenforced_required_approval")

    public static let known: [FailureMode] = [
        .answerKeyReachable, .graderDataReadable, .lengthExploit, .formatExploit, .judgeSycophancy,
        .testOverfit, .toolEscape, .rewardSaturation, .staleOracle, .nondeterministicGrader,
        .earlyTermination, .outputMimicry, .graderInjection, .sandboxPersistence, .specGaming,
        .omittedEpistemicRequirement, .ungradedExternality, .unenforcedRequiredApproval,
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

/// Source excerpt that shows the root cause. `code` is raw lines without numbers; the app numbers
/// them from `startLine` and emphasises `highlights` (absolute line numbers).
public struct CodeSnippet: Codable, Hashable, Sendable {
    public var path: String
    public var startLine: Int
    public var code: String
    public var highlights: [Int]
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
    /// Optional root-cause excerpt from the environment source.
    public var snippet: CodeSnippet?
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
/// One step of a rollout: what the policy did and what the environment returned.
public struct TraceStep: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case command, tool, message, observation }
    public var index: Int
    public var kind: Kind
    /// The command or tool call, or the text the policy wrote.
    public var action: String
    /// What came back, if anything.
    public var result: String?
    public var id: Int { index }

    public init(index: Int, kind: Kind, action: String, result: String? = nil) {
        self.index = index
        self.kind = kind
        self.action = action
        self.result = result
    }
}

/// How bad a hack is. High reached hidden grader state or the answer; medium gamed what was visible.
public enum HackSeverity: String, Codable, Sendable {
    case high, medium
    public var displayName: String { rawValue.capitalized }
}

/// One requirement of the task against what the rollout actually did. The rows behind "human intent
/// failed": a hack passes the reward's checks while failing these.
public struct OutcomeComparison: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The requirement, in the task's words.
    public var label: String
    public var expected: String
    public var observed: String
    public var failed: Bool
    /// What it means that this failed, if the backend says.
    public var consequence: String?
}

public struct Trajectory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var step: Int
    public var taskId: String
    /// Truncated task prompt.
    public var prompt: String
    /// Full model output (tool calls + text).
    public var output: String
    /// The rollout step by step. Optional on the wire; derived from `output` when absent.
    public var steps: [TraceStep]?
    /// Index into `steps` of the step that created the hack. Nil if clean or unknown.
    public var hackStep: Int?
    public var severity: HackSeverity?
    public var reward: RewardBreakdown
    public var graderNotes: String
    public var isHack: Bool
    /// Independent intent check: did the rollout achieve what the task meant? A hack is a high
    /// proxy reward with `intendedSuccess == false`. Optional for backends without an oracle.
    public var intendedSuccess: Bool?
    /// One human-readable line: what the policy did.
    public var summary: String
    /// Exact substring of `output` that constitutes the hack, for highlighting. Nil if clean.
    public var hackExcerpt: String?
    /// Raw text the judge / verifier returned for this rollout, when the reward is judge-based.
    public var judgeOutput: String?
    /// Pointer to the saved evidence this trajectory came from, e.g. `exploits/x.jsonl:2`.
    public var evidence: String?
    /// Requirement by requirement: what the task asked for against what happened.
    public var comparisons: [OutcomeComparison]?

    /// The rollout as steps. Backends that send only `output` get it split on `$ ` command lines;
    /// a free-text output is one message step.
    public var trace: [TraceStep] {
        if let steps, !steps.isEmpty { return steps }
        return TraceStep.derive(from: output)
    }

    /// The step that created the hack: `hackStep`, else the first step containing `hackExcerpt`.
    public var hackStepIndex: Int? {
        guard isHack else { return nil }
        if let hackStep { return hackStep }
        let steps = trace
        guard let excerpt = hackExcerpt?.split(separator: "\n").first.map(String.init) else { return steps.indices.last }
        return steps.firstIndex { $0.action.contains(excerpt) || ($0.result?.contains(excerpt) ?? false) } ?? steps.indices.last
    }

    public var hackSeverity: HackSeverity { severity ?? .high }
}

extension TraceStep {
    /// Split a terminal transcript into command steps. Lines starting with `$ ` begin a step; the
    /// lines until the next one are its result. Text with no commands is a single message step.
    public static func derive(from output: String) -> [TraceStep] {
        var steps: [TraceStep] = []
        var action: String?
        var result: [String] = []
        func close() {
            guard let a = action else { return }
            let r = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            steps.append(TraceStep(index: steps.count, kind: .command, action: a, result: r.isEmpty ? nil : r))
            action = nil
            result = []
        }
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("$ ") {
                close()
                action = String(line.dropFirst(2))
            } else if action != nil {
                result.append(String(line))
            }
        }
        close()
        if steps.isEmpty {
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [TraceStep(index: 0, kind: .message, action: text)]
        }
        return steps
    }
}

// MARK: Patch

/// What the policy is and is not allowed to learn from. A first-class concept of the product.
public struct LearningScope: Codable, Hashable, Sendable {
    public var allow: [String]
    public var deny: [String]
}

public enum ChangeKind: String, Codable, Sendable {
    case add, remove, alter
}

/// One proposed difference to one part of the environment, produced by hardening a hack.
/// `field` names the list or value inside the part: `constraints`, `visible`, `hidden`, `items`,
/// `actions`, `components`, `summary`, `termination`, `reset`, or `code` for the reward function.
public struct SpecChange: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var part: EnvironmentPart
    public var kind: ChangeKind
    public var field: String
    public var before: String?
    public var after: String?
    public var rationale: String
}

public struct Patch: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The hack this patch hardens against, when produced per hack.
    public var trajectoryId: String?
    public var findingIds: [String]
    /// Unified diff against the environment root.
    public var diff: String
    public var rationale: String
    public var learningScope: LearningScope
    /// Short bullet points describing what the patch changes.
    public var notes: [String]?
    /// Which parts of the environment the patch changes. Mirrors Matt's
    /// `contrast.expected_configuration_changes`.
    public var touches: [EnvironmentPart]?
    /// The differences, one per accept/reject decision. The unified `diff` is the code-level view of
    /// the `code` change on the Reward part.
    public var changes: [SpecChange]?
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

/// Verification replays two things on the patched environment: the attack that triggered liftoff
/// (must be blocked) and the legitimate reference trajectory (must still pass).
public struct ReplayCheck: Codable, Hashable, Sendable {
    public var attackBlocked: Bool
    public var legitimatePassed: Bool
}

public struct VerifyResult: Codable, Hashable, Sendable {
    public var runId: String
    public var before: RateSnapshot
    public var after: RateSnapshot
    public var stepsRerun: Int
    public var verdict: Verdict
    public var summary: String
    public var replay: ReplayCheck?
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
    /// Auditor version that produced this certificate; compared with `AppConfig.auditorVersion`.
    public var auditorVersion: String?
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
