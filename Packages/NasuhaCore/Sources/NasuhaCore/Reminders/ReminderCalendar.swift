import Foundation

/// When reminders fire.
public enum ReminderSchedule {
    /// The next `count` reminder times after `now`, at the chosen local time, following
    /// the frequency and skipping any pause. `calendar` must be Gregorian with the user's
    /// time zone (`Calendar.current` on device).
    public static func fireDates(after now: Date, settings: ReminderSettings, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        let anchorDay = calendar.startOfDay(for: settings.anchor ?? now)
        var day = calendar.startOfDay(for: now)
        var out: [Date] = []
        var looked = 0
        // Fridays need ~7 days per reminder; 1,000 days covers any window plus a long pause.
        while out.count < count, looked < 1_000 {
            looked += 1
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }
            guard includes(day, frequency: settings.frequency, anchorDay: anchorDay, calendar: calendar),
                  let fire = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
                  fire > now
            else { continue }
            if let pause = settings.pausedUntil, fire < pause { continue }
            out.append(fire)
        }
        return out
    }

    static func includes(_ day: Date, frequency: ReminderFrequency, anchorDay: Date, calendar: Calendar) -> Bool {
        switch frequency {
        case .daily:
            return true
        case .everyTwoDays:
            let n = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            return ((n % 2) + 2) % 2 == 0
        case .fridays:
            return calendar.component(.weekday, from: day) == 6
        }
    }
}

/// Hijri dates from the Umm al-Qura calendar, moved by the user's offset (−2…+2 days)
/// to match their local moon sighting.
public enum HijriDate {
    public struct Value: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int
    }

    public static func value(for date: Date, offset: Int, timeZone: TimeZone) -> Value {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = timeZone
        let shifted = cal.date(byAdding: .day, value: min(2, max(-2, offset)), to: date) ?? date
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        return Value(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    public static func isRamadan(_ date: Date, offset: Int, timeZone: TimeZone) -> Bool {
        value(for: date, offset: offset, timeZone: timeZone).month == 9
    }
}
