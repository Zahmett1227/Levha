import SwiftUI
import SwiftData

enum Sekme: String, Hashable {
    case bugun, levha, soru, olcum, icerik
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var faz
    @StateObject private var klasor = PaketKlasoru()
    @Bindable private var yonlendirici = Yonlendirici.ortak
    @State private var onPlandaBaslangic: Date?

    var body: some View {
        TabView(selection: $yonlendirici.sekme) {
            BugunView(sekme: $yonlendirici.sekme)
                .tabItem { Label("Bugün", systemImage: "sun.max") }
                .tag(Sekme.bugun)
            LevhaSekmesi()
                .tabItem { Label("Levha", systemImage: "square.grid.3x3.square") }
                .tag(Sekme.levha)
            SoruSekmesi()
                .tabItem { Label("Soru", systemImage: "questionmark.circle") }
                .tag(Sekme.soru)
            OlcumSekmesi()
                .tabItem { Label("Ölçüm", systemImage: "chart.bar.xaxis") }
                .tag(Sekme.olcum)
            IcerikView(klasor: klasor)
                .tabItem { Label("İçerik", systemImage: "tray.and.arrow.down") }
                .tag(Sekme.icerik)
        }
        .tint(Tema.metin)
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if UserDefaults.standard.bool(forKey: "fpsGoster") { FPSRozeti().padding(.top, 54).padding(.trailing, 8) }
        }
        #endif
        .task {
            LLMAyarlari.denetle()
            ABDeneyi.ortak.yukle(context)
            await Baslangic.calistir(klasor: klasor, context: context)
            Baslangic.soruAlanlariniDoldur(context)
            #if DEBUG
            YukTesti.calistir(context)
            #endif
            YedekServisi.otomatik(klasor: klasor, context)
            WidgetYazici.yaz(context)
            OlcumOnbellegi.ortak.isit(context.container, gecikme: .milliseconds(300))
        }
        // Her olay yazımından 1 sn sonra Ölçüm özeti arka planda tazelenir.
        .onChange(of: OlayDefteri.ortak.surum) { OlcumOnbellegi.ortak.isit(context.container) }
        .onOpenURL { url in
            if url.host() == "levha", let id = url.pathComponents.dropFirst().first, let levha = levhaBul(id) {
                UserDefaults.standard.set(levha.paket?.paket_id, forKey: "aktifPaketId")
            }
            yonlendirici.ac(url)
        }
        .onChange(of: faz, initial: true) { _, yeni in
            // Ön planda geçen süre günlük kullanım kaydına yazılır.
            if yeni == .active {
                onPlandaBaslangic = .now
                if klasor.kok != nil { YedekServisi.otomatik(klasor: klasor, context) }
            } else if let bas = onPlandaBaslangic {
                DurumServisi.kullanimEkle(Date.now.timeIntervalSince(bas), context)
                onPlandaBaslangic = nil
                WidgetYazici.yaz(context)
            }
        }
    }

    private func levhaBul(_ id: String) -> Levha? {
        try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first
    }
}
