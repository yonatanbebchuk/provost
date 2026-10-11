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

    // Data behind the visuals. Each visual reads only its own field; all are optional.
    public var names: [String]?
    public var timeline: [TimelineTick]?
    public var chart: ComputeShareChart?
    public var ring: RingStat?
    public var waffle: WaffleSpec?
    public var heroes: [HeroNumber]?
    public var team: [TeamLine]?

    public enum Visual: String, Codable, Sendable { case names, timeline, ring, reachDo, diagram, waffle, team }

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

    enum CodingKeys: String, CodingKey {
        case id, eyebrow, title, subtitle, visual, script, budgetSeconds, isDemoHandoff
        case names, timeline, chart, ring, waffle, heroes, team
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
        names = try c.decodeIfPresent([String].self, forKey: .names)
        timeline = try c.decodeIfPresent([TimelineTick].self, forKey: .timeline)
        chart = try c.decodeIfPresent(ComputeShareChart.self, forKey: .chart)
        ring = try c.decodeIfPresent(RingStat.self, forKey: .ring)
        waffle = try c.decodeIfPresent(WaffleSpec.self, forKey: .waffle)
        heroes = try c.decodeIfPresent([HeroNumber].self, forKey: .heroes)
        team = try c.decodeIfPresent([TeamLine].self, forKey: .team)
    }
}

/// The deck file: `{ "slides": [...] }`.
public struct PitchDeck: Codable, Sendable {
    public var slides: [PitchSlide]

    /// `PROFOS_DECK=/path/to/deck.json` (set by `make pitch`) wins over the bundled copy, so edits to
    /// the source file land on ⌘R without a rebuild.
    public static func locate() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PROFOS_DECK"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("pitch/deck.json")
    }

    public static func load(from url: URL) throws -> PitchDeck {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PitchDeck.self, from: data)
    }
}
