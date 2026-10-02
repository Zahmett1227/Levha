import SwiftUI
import SwiftData

/// "Levha" sekmesi: seçili alt konunun levha zinciri.
struct LevhaSekmesi: View {
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @AppStorage("aktifPaketId") private var aktifPaketId = ""
    @State private var mod: LevhaModu = .kesif
    private var yonlendirici = Yonlendirici.ortak

    var body: some View {
        NavigationStack {
            Group {
                let icerik = paketler.filter { !$0.kullaniciMi }
                if let paket = icerik.first(where: { $0.paket_id == aktifPaketId }) ?? icerik.first {
                    LevhaPager(levhalar: paket.siraliLevhalar, mod: $mod, onek: paket.bolum,
                               baslangicId: yonlendirici.hedefLevhaId) {
                        Menu {
                            ForEach(icerik) { p in
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
                    // Yeni açma isteği (deep link) zinciri hedef levhadan yeniden kurar.
                    .id("\(paket.paket_id)|\(yonlendirici.istek)")
                } else {
                    ContentUnavailableView("Henüz levha yok", systemImage: "square.dashed",
                                           description: Text("İçerik sekmesinden bir paket içe aktar."))
                }
            }
            .background(Tema.arkaPlan)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: yonlendirici.istek, initial: true) {
            if let m = yonlendirici.hedefMod { mod = m }
        }
    }
}

/// Levha zinciri: üstte "‹önek› · Levha i/n · Tip", sağa/sola kaydırınca sonraki/önceki levha.
struct LevhaPager<Sag: View>: View {
    let levhalar: [Levha]
    @Binding var mod: LevhaModu
    var izinliModlar: [LevhaModu] = LevhaModu.allCases
    let onek: String
    var baslangicId: String?
    var bildir: (LevhaOlayi) -> Void = { _ in }
    @ViewBuilder var sag: Sag

    @State private var indeks = 0
    @State private var hazir = false

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
        .onAppear {
            guard !hazir else { return }
            hazir = true
            if let id = baslangicId, let i = levhalar.firstIndex(where: { $0.id == id }) { indeks = i }
        }
    }
}
