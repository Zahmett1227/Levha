import AppIntents

/// "Levha turu": uygulamayı Bugün sekmesinde açar (Kısayollar, Siri, Spotlight).
struct LevhaTuruIntent: AppIntent {
    static var title: LocalizedStringResource = "Levha turu"
    static var description = IntentDescription("Levha'yı Bugün sekmesinde, günlük turla açar.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Yonlendirici.ortak.sekme = .bugun
        return .result()
    }
}

struct LevhaKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LevhaTuruIntent(),
                    phrases: ["\(.applicationName) turu", "\(.applicationName) turunu aç"],
                    shortTitle: "Levha turu",
                    systemImageName: "sun.max")
    }
}
