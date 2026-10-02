import SwiftUI
import SwiftData

/// "Levha" sekmesi: seçili alt konunun levha zinciri.
struct LevhaSekmesi: View {
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @AppStorage("aktifPaketId") private var aktifPaketId = ""

    var body: some View {
        NavigationStack {
            Group {
                if let paket = paketler.first(where: { $0.paket_id == aktifPaketId }) ?? paketler.first {
                    LevhaZinciriView(paket: paket, paketler: paketler) { aktifPaketId = $0 }
                        .id(paket.paket_id)
                } else {
                    ContentUnavailableView("Henüz levha yok", systemImage: "square.dashed",
                                           description: Text("İçerik sekmesinden bir paket içe aktar."))
                }
            }
            .background(Tema.arkaPlan)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Alt konunun levhaları; sağa/sola kaydırınca sonraki/önceki levha.
struct LevhaZinciriView: View {
    let paket: Paket
    let paketler: [Paket]
    let paketSec: (String) -> Void

    @State private var indeks = 0
    @State private var mod: LevhaModu = .kesif

    var body: some View {
        let levhalar = paket.siraliLevhalar
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if levhalar.indices.contains(indeks) {
                    let l = levhalar[indeks]
                    Text("\(paket.bolum) · Levha \(indeks + 1)/\(levhalar.count) · \(l.tipAdi)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Tema.ikincil)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Menu {
                    ForEach(paketler) { p in
                        Button {
                            paketSec(p.paket_id)
                        } label: {
                            if p.paket_id == paket.paket_id {
                                Label("\(p.bolum) › \(p.alt_konu)", systemImage: "checkmark")
                            } else {
                                Text("\(p.bolum) › \(p.alt_konu)")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                        .frame(width: 32, height: 28)
                }
                .accessibilityLabel("Alt konu seç")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            TabView(selection: $indeks) {
                ForEach(Array(levhalar.enumerated()), id: \.element.id) { i, levha in
                    LevhaSayfasi(levha: levha, mod: $mod)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Tema.arkaPlan)
    }
}
