import SwiftUI
import SwiftData

/// Zincirdeki tek bir levha: başlık, akılda kalan şeridi, mod seçici, levha kartı, not paneli.
struct LevhaSayfasi: View {
    let levha: Levha
    @Binding var mod: LevhaModu

    @Environment(\.modelContext) private var context
    @State private var katman = 1
    @State private var secili: String?
    @State private var acilan: Set<String> = []
    @State private var asama: OrtmeAsamasi = .aciliyor
    @State private var bilemedikler: Set<String> = []

    enum OrtmeAsamasi: Equatable {
        case aciliyor
        case degerlendir
        case bilemediklerSec
        case kaydedildi(bildim: Int, bilemedim: Int)
    }

    private var cizilebilir: Bool { levha.levhaTipi?.cizilebilir == true }

    /// Örtme sırasındaki ilk 3 (var olan) düğüm.
    private var hedefler: [String] {
        let idler = Set(levha.dugumler.map(\.id))
        return Array(levha.ortme_sirasi.filter { idler.contains($0) }.prefix(3))
    }

    private var durum: LevhaGorunumDurumu {
        switch mod {
        case .ortme:
            return LevhaGorunumDurumu(mod: .ortme, katman: LevhaGorunumDurumu.katmanSayisi, secili: nil,
                                      gizli: Set(hedefler).subtracting(acilan))
        default:
            return LevhaGorunumDurumu(mod: .kesif, katman: katman, secili: secili, gizli: [])
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(levha.baslik)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tema.metin)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            AkildaKalanSeridi(metin: levha.akilda_kalan)

            ModSecici(mod: $mod)
                .disabled(!cizilebilir)

            LevhaView(levha: levha, mode: durum, dokun: dugumeDokun)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .levhaKarti()
                .contentShape(RoundedRectangle(cornerRadius: Tema.kartKose))
                .onTapGesture(perform: kartaDokun)
                .accessibilityAction(named: "Sonraki katman", kartaDokun)

            NotPaneli {
                if !cizilebilir {
                    PanelBasligi(ust: levha.tipAdi.uppercased(), alt: nil)
                    Text("Bu levha içe aktarıldı; bu tipin çizimi Part 2'de gelecek.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tema.ikincil)
                } else if mod == .ortme {
                    ortmePaneli
                } else {
                    kesifPaneli
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .sensoryFeedback(.selection, trigger: katman)
        .sensoryFeedback(.impact(weight: .light), trigger: acilan.count)
        .onChange(of: mod) { sifirla() }
    }

    // MARK: - Etkileşim

    private func kartaDokun() {
        guard cizilebilir, mod == .kesif else { return }
        if katman < LevhaGorunumDurumu.katmanSayisi {
            withAnimation(.easeOut(duration: 0.25)) { katman += 1 }
            if katman == LevhaGorunumDurumu.katmanSayisi { calisildi() }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { secili = nil }
        }
    }

    private func dugumeDokun(_ id: String) {
        switch mod {
        case .kesif:
            guard katman >= LevhaGorunumDurumu.katmanSayisi else { return kartaDokun() }
            withAnimation(.easeOut(duration: 0.25)) { secili = secili == id ? nil : id }
        case .ortme:
            guard durum.gizli.contains(id) else { return }
            withAnimation(.easeOut(duration: 0.25)) { _ = acilan.insert(id) }
            if Set(hedefler).isSubset(of: acilan) {
                withAnimation(.easeOut(duration: 0.25)) { asama = .degerlendir }
            }
        case .sabotaj:
            break
        }
    }

    private func kaydet(bilemedikler: Set<String>) {
        let simdi = Date.now
        for id in hedefler {
            context.insert(OrtmeOlayi(levhaId: levha.id, dugumId: id, tarih: simdi, bildim: !bilemedikler.contains(id)))
        }
        levha.sonCalisma = simdi
        try? context.save()
        withAnimation(.easeOut(duration: 0.25)) {
            asama = .kaydedildi(bildim: hedefler.count - bilemedikler.count, bilemedim: bilemedikler.count)
        }
    }

    private func calisildi() {
        levha.sonCalisma = .now
        try? context.save()
    }

    private func sifirla() {
        withAnimation(.easeOut(duration: 0.25)) {
            katman = 1
            secili = nil
            acilan = []
            asama = .aciliyor
            bilemedikler = []
        }
    }

    // MARK: - Paneller

    private static let katmanAdlari: [LevhaTipi: [String]] = [
        .algoritma: ["Düğümler", "Bağlantılar", "TUS vurguları", "Notlar"],
        .matris: ["Başlıklar", "Hücreler", "TUS vurguları", "Notlar"],
        .sayi_cetveli: ["İşaretler", "Değerler", "TUS vurguları", "Notlar"],
    ]

    private var katmanAdlari: [String] {
        Self.katmanAdlari[levha.levhaTipi ?? .algoritma] ?? ["1", "2", "3", "4"]
    }

    @ViewBuilder
    private var kesifPaneli: some View {
        let toplam = LevhaGorunumDurumu.katmanSayisi
        HStack(spacing: 8) {
            PanelBasligi(ust: "KATMAN \(katman)/\(toplam)", alt: katmanAdlari[katman - 1])
            Spacer()
            KatmanNoktalari(katman: katman, toplam: toplam)
            if katman == toplam {
                Button("Baştan", action: sifirla)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.ikincil)
            }
        }
        if let id = secili, let d = levha.dugumler.first(where: { $0.id == id }) {
            let renk = RenkSeti.ad(d.renk)
            Text(d.etiket)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(renk.yazi)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ScrollView {
                Text(d.not.isEmpty ? "Bu düğüm için not yok." : d.not)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.metin)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        } else if katman < toplam {
            Text("Levhaya dokun → \(katmanAdlari[katman])")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        } else {
            Text("Bir düğüme dokun; notu burada açılır.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        }
    }

    @ViewBuilder
    private var ortmePaneli: some View {
        let toplam = hedefler.count
        HStack(spacing: 8) {
            PanelBasligi(ust: "ÖRTME", alt: "Açılan \(acilan.count)/\(toplam)")
            Spacer()
            KatmanNoktalari(katman: acilan.count, toplam: toplam)
        }
        switch asama {
        case _ where toplam == 0:
            Text("Bu levhada örtme sırası yok.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        case .aciliyor:
            Text("Önce cevabı içinden söyle, sonra gizli düğüme dokun.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        case .degerlendir:
            HStack(spacing: 10) {
                PanelDugmesi(baslik: "Hepsini bildim", renk: .yesil, dolu: true) { kaydet(bilemedikler: []) }
                PanelDugmesi(baslik: "Bilemediğim vardı", renk: .kirmizi, dolu: false) {
                    withAnimation(.easeOut(duration: 0.25)) { asama = .bilemediklerSec }
                }
            }
        case .bilemediklerSec:
            HStack(spacing: 6) {
                ForEach(hedefler, id: \.self) { id in
                    let etiket = levha.dugumler.first(where: { $0.id == id })?.etiket ?? id
                    let secildi = bilemedikler.contains(id)
                    Button {
                        if secildi { bilemedikler.remove(id) } else { bilemedikler.insert(id) }
                    } label: {
                        Text(etiket)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(secildi ? .white : RenkSeti.kirmizi.yazi)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(secildi ? RenkSeti.kirmizi.kenar : RenkSeti.kirmizi.zemin, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(secildi ? .isSelected : [])
                }
            }
            HStack {
                Text("Bilemediklerini seç")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.ikincil)
                Spacer()
                Button("Kaydet") { kaydet(bilemedikler: bilemedikler) }
                    .font(.system(size: 14, weight: .bold))
                    .disabled(bilemedikler.isEmpty)
            }
        case .kaydedildi(let bildim, let bilemedim):
            HStack {
                Label("Kaydedildi · \(bildim) bildim, \(bilemedim) bilemedim", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RenkSeti.yesil.yazi)
                Spacer()
            }
            PanelDugmesi(baslik: "Baştan dene", renk: .gri, dolu: false, action: sifirla)
        }
    }
}

// MARK: - Parçalar

struct AkildaKalanSeridi: View {
    let metin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AKILDA KALAN")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(RenkSeti.sari.zemin.opacity(0.85))
            Text(metin)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ModSecici: View {
    @Binding var mod: LevhaModu

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LevhaModu.allCases) { m in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mod = m }
                } label: {
                    HStack(spacing: 4) {
                        Text(m.ad)
                        if !m.aktif { Image(systemName: "lock.fill").font(.system(size: 9)) }
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(mod == m ? Color.white : (m.aktif ? Tema.metin : Tema.cizgi))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(mod == m ? Tema.metin : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!m.aktif)
                .accessibilityHint(m.aktif ? "" : "Part 2'de açılacak")
                .accessibilityAddTraits(mod == m ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
    }
}

struct NotPaneli<Icerik: View>: View {
    @ViewBuilder var icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { icerik }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 156, alignment: .topLeading)
            .levhaKarti()
    }
}

struct PanelBasligi: View {
    let ust: String
    let alt: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(ust)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Tema.ikincil)
            if let alt {
                Text("·").foregroundStyle(Tema.cizgi)
                Text(alt)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.metin)
            }
        }
    }
}

struct KatmanNoktalari: View {
    let katman: Int
    let toplam: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(toplam, 0), id: \.self) { i in
                Capsule()
                    .fill(i < katman ? Tema.metin : Tema.kartKenar)
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PanelDugmesi: View {
    let baslik: String
    let renk: RenkSeti
    let dolu: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(baslik)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(dolu ? Color.white : renk.yazi)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(dolu ? renk.kenar : renk.zemin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(renk.kenar, lineWidth: dolu ? 0 : 1.5))
        }
        .buttonStyle(.plain)
    }
}
