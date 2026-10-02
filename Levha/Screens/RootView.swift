import SwiftUI
import SwiftData

enum Sekme: String, Hashable {
    case bugun, levha, soru, sor, icerik
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var klasor = PaketKlasoru()
    @State private var sekme: Sekme = Sekme(rawValue: UserDefaults.standard.string(forKey: "baslangicSekme") ?? "") ?? .bugun
    @Query private var sorular: [Soru]

    var body: some View {
        TabView(selection: $sekme) {
            BugunView(sekme: $sekme)
                .tabItem { Label("Bugün", systemImage: "sun.max") }
                .tag(Sekme.bugun)
            LevhaSekmesi()
                .tabItem { Label("Levha", systemImage: "square.grid.3x3.square") }
                .tag(Sekme.levha)
            YerTutucu(baslik: "Soru modu Part 2'de", simge: "questionmark.circle",
                      aciklama: "\(sorular.count) soru içe aktarıldı. Cevap yolu animasyonlu Soru modu Part 2'de açılacak.")
                .tabItem { Label("Soru", systemImage: "questionmark.circle") }
                .tag(Sekme.soru)
            YerTutucu(baslik: "Sor Part 4'te", simge: "bubble.left.and.text.bubble.right",
                      aciklama: "Levha bağlamıyla Claude'a soru sorma Part 4'te gelecek.")
                .tabItem { Label("Sor", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Sekme.sor)
            IcerikView(klasor: klasor)
                .tabItem { Label("İçerik", systemImage: "tray.and.arrow.down") }
                .tag(Sekme.icerik)
        }
        .tint(Tema.metin)
        .task { await Baslangic.calistir(klasor: klasor, context: context) }
    }
}

struct YerTutucu: View {
    let baslik: String
    let simge: String
    let aciklama: String

    var body: some View {
        ContentUnavailableView(baslik, systemImage: simge, description: Text(aciklama))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tema.arkaPlan)
    }
}
