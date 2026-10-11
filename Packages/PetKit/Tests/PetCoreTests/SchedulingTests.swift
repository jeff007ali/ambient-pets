import Foundation
import Testing
@testable import PetCore

let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ cal: Calendar = newYork) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Suite struct QuietHoursTests {
    let overnight = QuietHours(enabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)

    @Test(arguments: [
        (21, 59, false), (22, 0, true), (23, 30, true), (0, 0, true), (7, 59, true), (8, 0, false), (12, 0, false),
    ])
    func overnightRange(_ h: Int, _ m: Int, _ expected: Bool) {
        #expect(overnight.contains(date(2026, 6, 10, h, m), calendar: newYork) == expected)
    }

    @Test func sameDayRange() {
        let lunch = QuietHours(enabled: true, startMinutes: 12 * 60, endMinutes: 13 * 60)
        #expect(lunch.contains(date(2026, 6, 10, 12, 30), calendar: newYork))
        #expect(!lunch.contains(date(2026, 6, 10, 13, 0), calendar: newYork))
        #expect(!lunch.contains(date(2026, 6, 10, 11, 59), calendar: newYork))
    }

    @Test func disabledOrEmptyNeverMatches() {
        #expect(!QuietHours(enabled: false).contains(date(2026, 6, 10, 23), calendar: newYork))
        #expect(!QuietHours(enabled: true, startMinutes: 600, endMinutes: 600).contains(date(2026, 6, 10, 10), calendar: newYork))
    }

    @Test func endIsNextMorning() {
        let end = overnight.end(after: date(2026, 6, 10, 23), calendar: newYork)
        #expect(end == date(2026, 6, 11, 8))
        #expect(overnight.end(after: date(2026, 6, 11, 3), calendar: newYork) == date(2026, 6, 11, 8))
        #expect(overnight.end(after: date(2026, 6, 11, 12), calendar: newYork) == nil)
    }

    @Test func springForwardNightIsAnHourShorter() {
        // 2026-03-08 02:00 EST → 03:00 EDT.
        let start = date(2026, 3, 7, 23)
        let end = overnight.end(after: start, calendar: newYork)!
        #expect(end == date(2026, 3, 8, 8))
        #expect(end.timeIntervalSince(start) == 8 * 3600)
        #expect(overnight.contains(date(2026, 3, 8, 3, 30), calendar: newYork))
    }

    @Test func fallBackNightIsAnHourLonger() {
        // 2026-11-01 02:00 EDT → 01:00 EST.
        let start = date(2026, 10, 31, 23)
        let end = overnight.end(after: start, calendar: newYork)!
        #expect(newYork.component(.hour, from: end) == 8)
        #expect(end.timeIntervalSince(start) == 10 * 3600)
    }

    @Test func repeatedHourDuringFallBack() {
        let q = QuietHours(enabled: true, startMinutes: 60, endMinutes: 3 * 60)
        let firstOneThirty = date(2026, 11, 1, 1, 30)
        let secondOneThirty = firstOneThirty + 3600
        #expect(q.contains(firstOneThirty, calendar: newYork))
        #expect(q.contains(secondOneThirty, calendar: newYork))
        #expect(newYork.component(.hour, from: q.end(after: firstOneThirty, calendar: newYork)!) == 3)
    }
}

@Suite struct SchedulerTests {
    let scheduler = Scheduler(calendar: newYork)
    let now = date(2026, 6, 10, 14)
    let open = ContextPolicy(paused: false)

    @Test func intervalStaysWithinBounds() {
        let rng = SeededRandom(seed: 42)
        let s = AppSettings() // 3–15 min
        var sum = 0.0
        for _ in 0..<10_000 {
            let d = scheduler.nextDelay(settings: s, policy: open, lastAppearance: nil, now: now, rng: rng)
            #expect(d >= 180 && d <= 900)
            sum += d
        }
        #expect(abs(sum / 10_000 - 540) < 10)
    }

    @Test func contextMultiplierAndActivityScaleTheInterval() {
        let rng = SeededRandom(seed: 7)
        var s = AppSettings()
        s.cooldownMinutes = 0
        let busy = ContextPolicy(paused: false, frequencyMultiplier: 2)
        for _ in 0..<2_000 {
            let d = scheduler.nextDelay(settings: s, policy: busy, activity: 1.5, lastAppearance: nil, now: now, rng: rng)
            #expect(d >= 60 && d <= 300) // 180/3 … 900/3
        }
    }

    @Test func swappedMinMaxStillWorks() {
        var s = AppSettings()
        s.minIntervalMinutes = 10
        s.maxIntervalMinutes = 5
        let d = scheduler.nextDelay(settings: s, policy: open, lastAppearance: nil, now: now, rng: SeededRandom(seed: 1))
        #expect(d >= 300 && d <= 600)
    }

    @Test func cooldownClampsTheDelay() {
        var s = AppSettings()
        s.minIntervalMinutes = 0.1
        s.maxIntervalMinutes = 0.1
        s.cooldownMinutes = 2
        let d = scheduler.nextDelay(settings: s, policy: open, lastAppearance: now - 30, now: now, rng: SeededRandom(seed: 1))
        #expect(d == 90)
    }

    @Test func neverBelowMinimumDelay() {
        var s = AppSettings()
        s.minIntervalMinutes = 0
        s.maxIntervalMinutes = 0
        s.cooldownMinutes = 0
        let d = scheduler.nextDelay(settings: s, policy: ContextPolicy(paused: false, frequencyMultiplier: 100),
                                    lastAppearance: nil, now: now, rng: SeededRandom(seed: 1))
        #expect(d == scheduler.minimumDelay)
    }

    func gates(_ configure: (inout GateInputs) -> Void) -> GateResult {
        var g = GateInputs(now: now, settings: AppSettings(), policy: open)
        configure(&g)
        return scheduler.evaluateGates(g, rng: SeededRandom(seed: 3))
    }

    @Test func openByDefault() {
        #expect(gates { _ in } == .open)
    }

    @Test func disabledDoesNotRetryOnATimer() {
        #expect(gates { $0.settings.enabled = false } == .blocked(.disabled, retryAt: nil))
    }

    @Test func disabledWinsOverEverythingElse() {
        let r = gates {
            $0.settings.enabled = false
            $0.isLocked = true
            $0.settings.quietHours = QuietHours(enabled: true, startMinutes: 0, endMinutes: 23 * 60)
        }
        #expect(r == .blocked(.disabled, retryAt: nil))
    }

    @Test func pauseRetriesShortlyAfterItEnds() {
        guard case .blocked(.paused, let retry?) = gates({ $0.pausedUntil = now + 3600 }) else {
            Issue.record("expected paused"); return
        }
        #expect(retry > now + 3600 && retry < now + 3600 + 120)
        #expect(gates { $0.pausedUntil = now - 1 } == .open)
    }

    @Test func quietHoursRetryAtTheirEnd() {
        let r = gates {
            $0.now = date(2026, 6, 10, 23)
            $0.settings.quietHours = QuietHours(enabled: true, startMinutes: 22 * 60, endMinutes: 8 * 60)
        }
        guard case .blocked(.quietHours, let retry?) = r else { Issue.record("expected quiet hours"); return }
        #expect(retry > date(2026, 6, 11, 8) && retry < date(2026, 6, 11, 8, 2))
    }

    @Test func lockedWaitsForUnlockEvent() {
        #expect(gates { $0.isLocked = true } == .blocked(.locked, retryAt: nil))
    }

    @Test func dailyLimitRetriesTomorrow() {
        guard case .blocked(.dailyLimit, let retry?) = gates({ $0.appearancesToday = 40 }) else {
            Issue.record("expected daily limit"); return
        }
        #expect(newYork.isDate(retry, inSameDayAs: date(2026, 6, 11, 0)))
        #expect(gates { $0.appearancesToday = 39 } == .open)
        #expect(gates { $0.appearancesToday = 1000; $0.settings.dailyLimit = 0 } == .open) // 0 = unlimited
    }

    @Test func dailyLimitResetsAtMidnight() {
        var h = EventHistory()
        for i in 0..<40 {
            h.record(AppearanceEvent(date: date(2026, 6, 9, 10) + Double(i) * 60, petID: "p", sceneID: "s\(i)", tier: .quick))
        }
        #expect(h.count(onSameDayAs: date(2026, 6, 9, 23), calendar: newYork) == 40)
        #expect(h.count(onSameDayAs: date(2026, 6, 10, 0, 1), calendar: newYork) == 0)
    }

    @Test func contextPauseBacksOffBriefly() {
        guard case .blocked(.contextPaused, let retry?) = gates({ $0.policy = .pausedPolicy }) else {
            Issue.record("expected context pause"); return
        }
        #expect(retry >= now + 60 && retry <= now + 120)
    }

    @Test func underLoadRespectsSetting() {
        if case .blocked(.underLoad, _) = gates({ $0.underLoad = true }) {} else { Issue.record("expected under load") }
        #expect(gates { $0.underLoad = true; $0.settings.skipUnderLoad = false } == .open)
    }
}

@Suite struct ContextTests {
    @Test func classifierPriority() {
        var s = ContextSignals(idleSeconds: 999)
        s.isGaming = true
        s.inMeeting = true
        #expect(ContextClassifier.classify(s, idleThreshold: 120) == .videoCall)
        s.isLocked = true
        #expect(ContextClassifier.classify(s, idleThreshold: 120) == .locked)
        #expect(ContextClassifier.classify(ContextSignals(idleSeconds: 999), idleThreshold: 120) == .idle)
        #expect(ContextClassifier.classify(ContextSignals(idleSeconds: 5), idleThreshold: 120) == .activeWork)
    }

    @Test func pausedStatesHaveNoTiers() {
        for state in [ContextState.fullScreen, .presentation, .videoCall, .gaming, .locked] {
            let p = PolicyTable.policy(for: state, settings: AppSettings())
            #expect(p.paused, "\(state)")
        }
    }

    @Test func userTogglesOverridePauses() {
        var s = AppSettings()
        s.pauseWhileGaming = false
        #expect(!PolicyTable.policy(for: .gaming, settings: s).paused)
        #expect(PolicyTable.policy(for: .videoCall, settings: s).paused)
        s.debugAllowOverFullScreen = true
        #expect(!PolicyTable.policy(for: .fullScreen, settings: s).paused)
    }

    @Test func soundsOffMeansNoAudio() {
        #expect(!PolicyTable.policy(for: .idle, settings: AppSettings()).audioAllowed)
        var s = AppSettings()
        s.soundsEnabled = true
        #expect(PolicyTable.policy(for: .idle, settings: s).audioAllowed)
        #expect(!PolicyTable.policy(for: .activeWork, settings: s).audioAllowed)
    }
}
