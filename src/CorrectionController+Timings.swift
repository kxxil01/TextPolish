import Foundation

/// Shows a repeated notice, such as "Correction in progress", at most once per cooldown.
struct FeedbackCooldown: Sendable {
  private var lastShown: ContinuousClock.Instant?
  let cooldown: Duration

  init(cooldown: Duration) {
    self.cooldown = cooldown
  }

  mutating func shouldShow(now: ContinuousClock.Instant) -> Bool {
    if let lastShown, now < lastShown + cooldown {
      return false
    }
    self.lastShown = now
    return true
  }
}

extension CorrectionController {
  struct Timings: Sendable {
    let activationDelay: Duration
    let selectAllDelay: Duration
    let copySettleDelay: Duration
    let copyTimeout: Duration
    let pasteSettleDelay: Duration
    let postPasteDelay: Duration

    static let `default` = Timings(
      activationDelay: .milliseconds(80),
      selectAllDelay: .milliseconds(60),
      copySettleDelay: .milliseconds(20),
      copyTimeout: .milliseconds(900),
      pasteSettleDelay: .milliseconds(25),
      postPasteDelay: .milliseconds(180)
    )

    init(
      activationDelay: Duration,
      selectAllDelay: Duration,
      copySettleDelay: Duration,
      copyTimeout: Duration,
      pasteSettleDelay: Duration,
      postPasteDelay: Duration
    ) {
      self.activationDelay = activationDelay
      self.selectAllDelay = selectAllDelay
      self.copySettleDelay = copySettleDelay
      self.copyTimeout = copyTimeout
      self.pasteSettleDelay = pasteSettleDelay
      self.postPasteDelay = postPasteDelay
    }

    init(settings: Settings) {
      activationDelay = Timings.duration(milliseconds: settings.activationDelayMilliseconds)
      selectAllDelay = Timings.duration(milliseconds: settings.selectAllDelayMilliseconds)
      copySettleDelay = Timings.duration(milliseconds: settings.copySettleDelayMilliseconds)
      copyTimeout = Timings.duration(milliseconds: settings.copyTimeoutMilliseconds)
      pasteSettleDelay = Timings.duration(milliseconds: settings.pasteSettleDelayMilliseconds)
      postPasteDelay = Timings.duration(milliseconds: settings.postPasteDelayMilliseconds)
    }

    static func duration(milliseconds value: Int) -> Duration {
      .milliseconds(Int64(max(0, value)))
    }

    func applying(_ profile: Settings.TimingProfile) -> Timings {
      Timings(
        activationDelay: profile.activationDelayMilliseconds.map(Timings.duration) ?? activationDelay,
        selectAllDelay: profile.selectAllDelayMilliseconds.map(Timings.duration) ?? selectAllDelay,
        copySettleDelay: profile.copySettleDelayMilliseconds.map(Timings.duration) ?? copySettleDelay,
        copyTimeout: profile.copyTimeoutMilliseconds.map(Timings.duration) ?? copyTimeout,
        pasteSettleDelay: profile.pasteSettleDelayMilliseconds.map(Timings.duration) ?? pasteSettleDelay,
        postPasteDelay: profile.postPasteDelayMilliseconds.map(Timings.duration) ?? postPasteDelay
      )
    }
  }
}
