import Foundation

/// Talks to the RL team's FastAPI server. Endpoints mirror `docs/contract.md`:
///
///   GET  /environments                      -> [AuditEnvironment]
///   POST /environments        {path}        -> AuditEnvironment
///   POST /runs                {env_id}      -> AuditRun
///   POST /runs/{id}/lint                    -> [LintFinding]
///   GET  /runs/{id}/train      (SSE)        -> TrainingEvent stream
///   POST /runs/{id}/patch                   -> Patch
///   GET  /runs/{id}/verify?patch_id= (SSE)  -> TrainingEvent stream
///   POST /runs/{id}/certificate             -> Certificate
///
/// SSE frames: `event: <point|trajectory|liftoff|phase|verify_result|completed>` + `data: <json>`.
public final class LocalHTTPBackend: AuditBackend {
    public let displayName: String
    private let base: URL
    private let session: URLSession

    public init(base: URL = AppConfig.localBackendURL, session: URLSession = .shared) {
        self.base = base
        self.session = session
        self.displayName = "Local HTTP · \(base.host ?? "")\(base.port.map { ":\($0)" } ?? "")"
    }

    public func listEnvironments() async throws -> [AuditEnvironment] {
        try await get("environments")
    }

    public func loadEnvironment(at url: URL) async throws -> AuditEnvironment {
        try await post("environments", body: ["path": url.path])
    }

    public func startAudit(envId: String, spec: EnvironmentSpec?) async throws -> AuditRun {
        struct Body: Encodable { let envId: String; let spec: EnvironmentSpec? }
        return try await post("runs", encoding: Body(envId: envId, spec: spec))
    }

    public func lint(runId: String) async throws -> [LintFinding] {
        try await post("runs/\(runId)/lint", body: [:])
    }

    public func train(runId: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        stream(path: "runs/\(runId)/train")
    }

    public func proposePatch(runId: String, trajectoryId: String?) async throws -> Patch {
        try await post("runs/\(runId)/patch", body: trajectoryId.map { ["trajectory_id": $0] } ?? [:])
    }

    public func verify(runId: String, patchId: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        stream(path: "runs/\(runId)/verify?patch_id=\(patchId)")
    }

    public func issueCertificate(runId: String) async throws -> Certificate {
        try await post("runs/\(runId)/certificate", body: [:])
    }

    // MARK: HTTP

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "GET"
        return try await send(req)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, encoding body: B) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ContractJSON.encoder.encode(body)
        return try await send(req)
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BackendError.transport("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.transport("HTTP \(http.statusCode) from \(req.url?.path ?? "?")")
        }
        do {
            return try ContractJSON.decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.decoding(req.url?.path ?? "response", underlying: String(describing: error))
        }
    }

    // MARK: SSE

    private func stream(path: String) -> AsyncThrowingStream<TrainingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: path, relativeTo: base) else { throw BackendError.transport("Bad URL \(path)") }
                    var req = URLRequest(url: url)
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 3600
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw BackendError.transport("SSE connect failed for \(path)")
                    }
                    var eventName = "message"
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if let event = Self.decodeEvent(name: eventName, data: dataLines.joined(separator: "\n")) {
                                continuation.yield(event)
                                if case .completed = event { break }
                            }
                            eventName = "message"
                            dataLines = []
                        } else if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func decodeEvent(name: String, data: String) -> TrainingEvent? {
        let payload = Data(data.utf8)
        let d = ContractJSON.decoder
        switch name {
        case "point": return (try? d.decode(TrainingPoint.self, from: payload)).map(TrainingEvent.point)
        case "trajectory": return (try? d.decode(Trajectory.self, from: payload)).map(TrainingEvent.trajectory)
        case "liftoff": return (try? d.decode(LiftoffEvent.self, from: payload)).map(TrainingEvent.liftoff)
        case "verify_result": return (try? d.decode(VerifyResult.self, from: payload)).map(TrainingEvent.verifyResult)
        case "phase":
            // data is either a bare string "training" or {"phase": "training"}
            if let p = try? d.decode(AuditPhase.self, from: payload) { return .phase(p) }
            if let obj = try? d.decode([String: AuditPhase].self, from: payload), let p = obj["phase"] { return .phase(p) }
            return nil
        case "completed": return .completed
        default: return nil
        }
    }
}
