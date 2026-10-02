import SwiftUI
import SwiftData

enum CalismaYeri: String, CaseIterable, Identifiable {
    case kitapli, kitapsiz, sadeceTekrar
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .kitapli: return "Kitaplı"
        case .kitapsiz: return "Kitapsız"
        case .sadeceTekrar: return "Sadece tekrar"
        }
    }
}

struct BugunView: View {
    @Binding var sekme: Sekme
    @AppStorage("calismaYeri") private var calismaYeri = CalismaYeri.kitapli.rawValue
    @AppStorage("aktifPaketId") private var aktifPaketId = ""
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Çalışma yeri", selection: $calismaYeri) {
                        ForEach(CalismaYeri.allCases) { Text($0.ad).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Bugün nerede çalışıyorsun?")
                }

                if paketler.isEmpty {
                    Section("Levhalar") {
                        Text("Henüz paket yok. İçerik sekmesinden içe aktar.")
                            .foregroundStyle(Tema.ikincil)
                    }
                }

                ForEach(dersler, id: \.self) { ders in
                    Section {
                        ForEach(bolumler(ders), id: \.self) { bolum in
                            Text(bolum.uppercased())
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(Tema.ikincil)
                                .listRowBackground(Tema.arkaPlan.opacity(0.6))
                            ForEach(paketler.filter { $0.ders == ders && $0.bolum == bolum }) { p in
                                Button {
                                    aktifPaketId = p.paket_id
                                    sekme = .levha
                                } label: {
                                    AltKonuSatiri(paket: p)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Levhalar · \(ders)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.arkaPlan)
            .navigationTitle("Bugün")
        }
    }

    private var dersler: [String] { tekil(paketler.map(\.ders)) }
    private func bolumler(_ ders: String) -> [String] { tekil(paketler.filter { $0.ders == ders }.map(\.bolum)) }
    private func tekil(_ dizi: [String]) -> [String] {
        var gorulen = Set<String>()
        return dizi.filter { gorulen.insert($0).inserted }
    }
}

struct AltKonuSatiri: View {
    let paket: Paket

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(paket.alt_konu)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tema.metin)
                Text("\(paket.levhalar.count) levha · \(paket.sonCalisma.map { "Son: \(Bicim.tarih($0))" } ?? "Henüz çalışılmadı")")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.ikincil)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.cizgi)
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
