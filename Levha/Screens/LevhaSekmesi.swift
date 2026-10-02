import SwiftUI
import SwiftData

/// "Levha" sekmesi: seçili alt konunun levha zinciri.
struct LevhaSekmesi: View {
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @AppStorage("aktifPaketId") private var aktifPaketId = ""
    @State private var mod: LevhaModu = .kesif

    var body: some View {
        NavigationStack {
            Group {
                if let paket = paketler.first(where: { $0.paket_id == aktifPaketId }) ?? paketler.first {
                    LevhaPager(levhalar: paket.siraliLevhalar, mod: $mod, onek: paket.bolum) {
                        Menu {
                            ForEach(paketler) { p in
                                Button {
                                    aktifPaketId = p.paket_id
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

/// Levha zinciri: üstte "‹önek› · Levha i/n · Tip", sağa/sola kaydırınca sonraki/önceki levha.
struct LevhaPager<Sag: View>: View {
    let levhalar: [Levha]
    @Binding var mod: LevhaModu
    var izinliModlar: [LevhaModu] = LevhaModu.allCases
    let onek: String
    var bildir: (LevhaOlayi) -> Void = { _ in }
    @ViewBuilder var sag: Sag

    @State private var indeks = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if levhalar.indices.contains(indeks) {
                    Text("\(onek) · Levha \(indeks + 1)/\(levhalar.count) · \(levhalar[indeks].tipAdi)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Tema.ikincil)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                sag
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .frame(minHeight: 28)

            TabView(selection: $indeks) {
                ForEach(Array(levhalar.enumerated()), id: \.element.id) { i, levha in
                    LevhaSayfasi(levha: levha, mod: $mod, izinliModlar: izinliModlar, bildir: bildir)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Tema.arkaPlan)
    }
}
