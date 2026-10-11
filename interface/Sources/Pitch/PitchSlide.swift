import Foundation

/// One slide of the pitch deck. Decoded from `Resources/pitch/deck.json`; the deck is data, the
/// views only render it. Titles, scripts and budgets are edited in the JSON, never here.
public struct PitchSlide: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var eyebrow: String?
    public var title: String
    public var subtitle: String?
    public var visual: Visual?
    /// Presenter notes: the spoken words only. Never shown on the slide.
    public var script: String
    public var budgetSeconds: Int
    /// True only on the Demo slide: `→` enters the app instead of advancing.
    public var isDemoHandoff: Bool
    /// The brand lockup stands in for the title.
    public var logo: Bool
    /// `"step"`: the visual builds one piece per `→` (ticks of a timeline, the chart); absent: it
    /// animates by itself when the slide appears.
    public var reveal: String?

    // Data behind the visuals. Each visual reads only its own field; all are optional.
    public var names: [String]?
    public var people: [Person]?
    public var timeline: [TimelineTick]?
    public var chart: ComputeShareChart?
    public var ring: RingStat?
    public var waffle: WaffleSpec?
    public var heroes: [HeroNumber]?
    public var team: [TeamLine]?
    /// Numbered lines, for the `lines` visual.
    public var lines: [String]?

    public enum Visual: String, Codable, Sendable { case names, faces, timeline, chart, ring, reachDo, diagram, waffle, heroes, lines, team }

    public struct Person: Codable, Hashable, Sendable {
        public var name: String
        /// GitHub handle; `scripts/fetch_faces.py` bundles its avatar as `faces/<handle>.png|jpg`.
        public var github: String?
        /// A photo in `Resources/pitch/faces/`, used over the GitHub avatar when set.
        public var image: String?
        public var initials: String {
            name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
        }
    }

    public struct TimelineTick: Codable, Hashable, Sendable {
        public var name: String
        public var product: String
    }

    /// Stacked-bar chart of compute share by workload, one bar per quarter.
    public struct ComputeShareChart: Codable, Hashable, Sendable {
        public struct Series: Codable, Hashable, Sendable {
            public var name: String
            public var values: [Double]
            public var highlight: Bool?
        }
        public var title: String
        public var source: String?
        public var quarters: [String]
        public var series: [Series]
    }

    public struct RingStat: Codable, Hashable, Sendable {
        public var percent: Int
        public var caption: String
    }

    public struct WaffleSpec: Codable, Hashable, Sendable {
        public var cells: Int
        public var columns: Int
        public var lit: Int
    }

    public struct HeroNumber: Codable, Hashable, Sendable {
        public var value: String
        /// When set, the number counts up from 0 to this and is formatted as currency.
        public var countTo: Int?
        public var accent: Bool?
        public var caption: String
    }

    public struct TeamLine: Codable, Hashable, Sendable {
        public var name: String
        public var clause: String
    }

    /// Long titles get a wider column, as the mock's `h1.wide`.
    public var isWideTitle: Bool { title.count > 45 }

    public var revealsByStep: Bool { reveal == "step" }

    /// How many `→` presses the slide takes before the next slide.
    public var buildCount: Int {
        guard revealsByStep else { return 0 }
        switch visual {
        case .timeline: return timeline?.count ?? 0
        case .chart: return 1
        default: return 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, eyebrow, title, subtitle, visual, script, budgetSeconds, isDemoHandoff, logo, reveal
        case names, people, timeline, chart, ring, waffle, heroes, team, lines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        eyebrow = try c.decodeIfPresent(String.self, forKey: .eyebrow)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        visual = try c.decodeIfPresent(Visual.self, forKey: .visual)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        budgetSeconds = try c.decodeIfPresent(Int.self, forKey: .budgetSeconds) ?? 0
        isDemoHandoff = try c.decodeIfPresent(Bool.self, forKey: .isDemoHandoff) ?? false
        logo = try c.decodeIfPresent(Bool.self, forKey: .logo) ?? false
        reveal = try c.decodeIfPresent(String.self, forKey: .reveal)
        names = try c.decodeIfPresent([String].self, forKey: .names)
        people = try c.decodeIfPresent([Person].self, forKey: .people)
        timeline = try c.decodeIfPresent([TimelineTick].self, forKey: .timeline)
        chart = try c.decodeIfPresent(ComputeShareChart.self, forKey: .chart)
        ring = try c.decodeIfPresent(RingStat.self, forKey: .ring)
        waffle = try c.decodeIfPresent(WaffleSpec.self, forKey: .waffle)
        heroes = try c.decodeIfPresent([HeroNumber].self, forKey: .heroes)
        team = try c.decodeIfPresent([TeamLine].self, forKey: .team)
        lines = try c.decodeIfPresent([String].self, forKey: .lines)
    }
}

/// The deck file: `{ "slides": [...] }`.
public struct PitchDeck: Codable, Sendable {
    public var slides: [PitchSlide]

    /// `PROVOST_DECK=/path/to/deck.json` (set by `make pitch`) wins over the bundled copy, so edits to
    /// the source file land on ⌘R without a rebuild.
    public static func locate() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PROVOST_DECK"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("pitch/deck.json")
    }

    /// The bundled face for a person: their `image` file, else the avatar `fetch_faces.py` saved
    /// for their GitHub handle.
    public static func faceURL(for person: PitchSlide.Person) -> URL? {
        guard let dir = locate()?.deletingLastPathComponent().appendingPathComponent("faces", isDirectory: true) else { return nil }
        var candidates: [String] = []
        if let image = person.image { candidates.append(image) }
        if let handle = person.github { candidates += ["\(handle).png", "\(handle).jpg"] }
        return candidates.map { dir.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(from url: URL) throws -> PitchDeck {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PitchDeck.self, from: data)
    }
}
