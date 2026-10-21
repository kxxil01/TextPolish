import Foundation

/// Requests and tokens per model for each month, saved next to the settings file on this Mac only.
/// Providers record from their request threads, so access is locked.
final class UsageLedger: @unchecked Sendable {
  struct Totals: Codable, Equatable, Sendable {
    var requests = 0
    var inputTokens = 0
    var outputTokens = 0
  }

  /// One model's use in a month.
  struct ModelUsage: Equatable, Sendable {
    let provider: Settings.Provider
    let model: String
    let totals: Totals

    var estimatedCost: Double? {
      ModelPricing.cost(model: model, inputTokens: totals.inputTokens, outputTokens: totals.outputTokens)
    }
  }

  static let shared = UsageLedger()
  static let monthsKept = 12

  private let lock = NSLock()
  private let fileURL: URL
  /// Month ("2026-10"), then "provider model", then totals.
  private var months: [String: [String: Totals]] = [:]

  init(fileURL: URL = UsageLedger.defaultFileURL) {
    self.fileURL = fileURL
    if let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode([String: [String: Totals]].self, from: data)
    {
      months = saved
    }
  }

  static var defaultFileURL: URL {
    Settings.settingsFileURL().deletingLastPathComponent().appendingPathComponent("usage.json", isDirectory: false)
  }

  /// Adds one request, with its token counts when the provider's response body reports them.
  func record(provider: Settings.Provider, model: String, responseBody: Data, at date: Date = Date()) {
    record(provider: provider, model: model, usage: TokenUsage.parse(responseBody), at: date)
  }

  func record(provider: Settings.Provider, model: String, usage: TokenUsage?, at date: Date = Date()) {
    lock.withLock {
      let month = Self.monthKey(date)
      let key = "\(provider.rawValue) \(model)"
      var totals = months[month, default: [:]][key, default: Totals()]
      totals.requests += 1
      totals.inputTokens += usage?.input ?? 0
      totals.outputTokens += usage?.output ?? 0
      months[month, default: [:]][key] = totals
      for old in months.keys.sorted().dropLast(Self.monthsKept) {
        months[old] = nil
      }
      save()
    }
  }

  /// Each model's use in the month of `date`, most used first.
  func usage(inMonthOf date: Date = Date()) -> [ModelUsage] {
    lock.withLock {
      (months[Self.monthKey(date)] ?? [:]).compactMap { key, totals in
        let parts = key.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = Settings.Provider(rawValue: parts[0]) else { return nil }
        return ModelUsage(provider: provider, model: parts[1], totals: totals)
      }
      .sorted { ($0.totals.requests, $0.model) > ($1.totals.requests, $1.model) }
    }
  }

  func clear() {
    lock.withLock {
      months = [:]
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  /// Lines for Diagnostics: the month's totals, the estimated cost, then each model.
  func summaryLines(inMonthOf date: Date = Date()) -> [String] {
    let models = usage(inMonthOf: date)
    guard !models.isEmpty else { return ["No requests yet this month."] }
    let requests = models.map(\.totals.requests).reduce(0, +)
    let input = models.map(\.totals.inputTokens).reduce(0, +)
    let output = models.map(\.totals.outputTokens).reduce(0, +)
    let costs = models.compactMap(\.estimatedCost)
    var total = "\(requests) requests, \(Self.count(input)) tokens in, \(Self.count(output)) out"
    if !costs.isEmpty {
      let partial = costs.count < models.count ? " for priced models" : ""
      total += ", about \(Self.dollars(costs.reduce(0, +)))\(partial)"
    }
    var lines = [total]
    for model in models {
      let cost = model.estimatedCost.map { "about \(Self.dollars($0))" } ?? "price not known"
      lines.append("• \(model.provider.displayName) \(model.model): \(model.totals.requests) requests, \(cost)")
    }
    lines.append("Estimates use list prices; your provider's bill is the final word.")
    return lines
  }

  private static func monthKey(_ date: Date) -> String {
    let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
  }

  private static func count(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
  }

  private static func dollars(_ value: Double) -> String {
    value < 0.01 && value > 0 ? "less than $0.01" : String(format: "$%.2f", value)
  }

  /// Called with the lock held.
  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(months).write(to: fileURL, options: .atomic)
    } catch {
      TPLogger.log("Could not save usage: \(error.localizedDescription)")
    }
  }
}
