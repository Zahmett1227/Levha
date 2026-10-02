import SwiftUI
import SwiftData

/// Levha sayfasının dışarıya bildirdiği olaylar (Günlük Tur blokları ilerlemeyi bununla sayar).
enum LevhaOlayi {
    case ortmeKaydedildi(levhaId: String)
    case sabotajBitti(levhaId: String, bulundu: Bool)
    case insaBitti(levhaId: String)
}

/// İnşa şeridindeki etiket çipi.
struct InsaCipi: Identifiable, Equatable {
    let id: String
    let etiket: String
    let renk: String
}

/// Zincirdeki tek bir levha: başlık, akılda kalan şeridi, mod seçici, levha kartı, not paneli.
struct LevhaSayfasi: View {
    let levha: Levha
    @Binding var mod: LevhaModu
    var izinliModlar: [LevhaModu] = LevhaModu.allCases
    var bildir: (LevhaOlayi) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @State private var katman = 1
    @State private var secili: String?
    // Örtme
    @State private var acilan: Set<String> = []
    @State private var asama: OrtmeAsamasi = .aciliyor
    @State private var bilemedikler: Set<String> = []
    @State private var hedefler: [String] = []
    // Sabotaj
    @State private var senaryo: SabotajSenaryosu?
    @State private var sabotajDeneme = 0
    @State private var sabotajAsama: SabotajAsamasi = .ariyor(yanlis: 0)
    // İnşa
    @State private var insaHedefler: [String] = []
    @State private var yerlesen: Set<String> = []
    @State private var ilkDenemeKacan: Set<String> = []
    @State private var cipler: [InsaCipi] = []
    @State private var seciliCip: String?
    @State private var insaHata = 0
    @State private var insaBaslangic = Date.now
    @State private var hataliMaske: String?
    @State private var sallama = 0
    @State private var insaDeneme = 0
    // Modele sor
    @State private var sorAcik = false

    enum OrtmeAsamasi: Equatable {
        case aciliyor
        case degerlendir
        case bilemediklerSec
        case kaydedildi(bildim: Int, bilemedim: Int)
    }

    enum SabotajAsamasi: Equatable {
        case ariyor(yanlis: Int)
        case bulundu(deneme: Int)
        case bulunamadi
    }

    private var durum: LevhaGorunumDurumu {
        switch mod {
        case .ortme:
            return LevhaGorunumDurumu(mod: .ortme, katman: LevhaGorunumDurumu.katmanSayisi,
                                      gizli: Set(hedefler).subtracting(acilan))
        case .sabotaj:
            // Hatalı hâl, Keşif'in son katmanı açık ama notlar kapalı.
            var d = LevhaGorunumDurumu(mod: .sabotaj, katman: LevhaGorunumDurumu.katmanSayisi)
            switch sabotajAsama {
            case .ariyor: d.dokunulabilir = senaryo != nil
            case .bulundu, .bulunamadi:
                for id in senaryo?.hedef ?? [] { d.halkalar[id] = .yesil }
            }
            return d
        case .kesif:
            return LevhaGorunumDurumu(mod: .kesif, katman: katman, secili: secili,
                                      dokunulabilir: katman >= LevhaGorunumDurumu.katmanSayisi)
        case .editor:
            return LevhaGorunumDurumu(mod: .kesif, katman: LevhaGorunumDurumu.katmanSayisi)
        case .insa:
            var d = LevhaGorunumDurumu(mod: .insa, katman: LevhaGorunumDurumu.katmanSayisi,
                                       gizli: Set(insaHedefler).subtracting(yerlesen))
            d.maskeStili = .bos
            d.maskeIpuclari = insaIpuclari
            d.hataliMaske = hataliMaske
            d.sallama = sallama
            for id in yerlesen { d.halkalar[id] = ilkDenemeKacan.contains(id) ? .sari : .yesil }
            return d
        }
    }

    private var insaBitti: Bool { !insaHedefler.isEmpty && yerlesen.count == insaHedefler.count }

    /// Boş kutuda kalan ipucu: cetvelde değer, zaman çizelgesinde zaman; diğer tiplerde konum yeterli.
    private var insaIpuclari: [String: String] {
        var sonuc: [String: String] = [:]
        for d in levha.dugumler where insaHedefler.contains(d.id) {
            switch levha.levhaTipi {
            case .sayi_cetveli:
                sonuc[d.id] = d.deger.map { "\(Bicim.sayi($0)) \(levha.eksenBirim)" } ?? "sabit değil"
            case .zaman_cizelgesi:
                let birim = ZamanBirimi(rawValue: levha.eksenBirim)?.ad ?? levha.eksenBirim
                let bas = Bicim.sayi(d.deger ?? 0)
                sonuc[d.id] = d.bit.map { "\(bas)–\(Bicim.sayi($0)) \(birim)" } ?? "\(bas). \(birim)"
            default:
                break
            }
        }
        return sonuc
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(levha.baslik)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Tema.metin)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { sorAcik = true } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                        .frame(width: 36, height: 30)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modele sor")
            }

            AkildaKalanSeridi(metin: levha.akilda_kalan)

            if izinliModlar.count > 1 {
                ModSecici(mod: $mod, izinli: izinliModlar)
            }

            if mod == .editor {
                EditorView(levha: levha)
            } else {
                LevhaView(levha: levha, mode: durum, cizim: mod == .sabotaj ? senaryo?.cizim : nil, dokun: dugumeDokun)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .levhaKarti()
                    .contentShape(RoundedRectangle(cornerRadius: Tema.kartKose))
                    .onTapGesture(perform: kartaDokun)
                    .accessibilityAction(named: "Sonraki katman", kartaDokun)

                NotPaneli(kenar: panelKenari) {
                    switch mod {
                    case .kesif, .editor: kesifPaneli
                    case .ortme: ortmePaneli
                    case .sabotaj: sabotajPaneli
                    case .insa: insaPaneli
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .sheet(isPresented: $sorAcik) {
            SorView(levha: levha, seciliDugumId: mod == .kesif ? secili : nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: katman)
        .sensoryFeedback(.impact(weight: .light), trigger: acilan.count)
        .sensoryFeedback(.error, trigger: sallama)
        .sensoryFeedback(.success, trigger: yerlesen.count)
        .sensoryFeedback(trigger: sabotajAsama) { _, yeni in
            switch yeni {
            case .bulundu: return .success
            case .ariyor(let y) where y > 0: return .warning
            case .bulunamadi: return .error
            default: return nil
            }
        }
        .onAppear(perform: hazirla)
        .onChange(of: mod) { sifirla() }
    }

    private var panelKenari: Color? {
        if mod == .sabotaj, case .ariyor(let y) = sabotajAsama, y > 0 { return RenkSeti.sari.kenar }
        return nil
    }

    // MARK: - Hazırlık

    private func hazirla() {
        if !izinliModlar.contains(mod), let ilk = izinliModlar.first { mod = ilk }
        hedefleriSec()
        sabotajKur()
        insaKur()
    }

    /// İnşa: insa_sirasi (yoksa ortme_sirasi) düğümleri boş kalır, etiketleri tohumlu karışık çip olur.
    private func insaKur() {
        let idler = Set(levha.dugumler.map(\.id))
        insaHedefler = (levha.insa_sirasi ?? levha.ortme_sirasi).filter { idler.contains($0) }
        var rng = TohumluUretec(tohum: "insa|\(levha.id)|\(DurumServisi.gunAnahtari())|\(insaDeneme)")
        cipler = insaHedefler.compactMap { id in
            levha.dugumler.first { $0.id == id }.map { InsaCipi(id: id, etiket: $0.etiket, renk: $0.renk) }
        }.shuffled(using: &rng)
        yerlesen = []
        ilkDenemeKacan = []
        seciliCip = nil
        insaHata = 0
        hataliMaske = nil
        insaBaslangic = .now
    }

    /// Örtme maskesi: `ortme_sirasi` düğüm zayıflığına göre yeniden sıralanır (zayıf öne), ilk 3'ü gizlenir.
    private func hedefleriSec() {
        let idler = Set(levha.dugumler.map(\.id))
        let zayiflik = DurumServisi.zayifliklar(levha.id, context)
        let sira = levha.ortme_sirasi.filter { idler.contains($0) }
        hedefler = Array(sira.enumerated()
            .sorted { (zayiflik[$0.element] ?? 0, -$0.offset) > (zayiflik[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
            .prefix(3))
    }

    private func sabotajKur() {
        let tohum = "\(levha.id)|\(DurumServisi.gunAnahtari())|\(sabotajDeneme)"
        senaryo = MutasyonMotoru.sec(LevhaCizim(levha), yazilmis: levha.yazilmisSabotajlar, tohum: tohum)
        sabotajAsama = .ariyor(yanlis: 0)
    }

    // MARK: - Etkileşim

    private func kartaDokun() {
        guard mod == .kesif else { return }
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
        case .insa:
            insaYerlestir(id)
        case .editor:
            break
        case .sabotaj:
            guard let s = senaryo, case .ariyor(let yanlis) = sabotajAsama else { return }
            if s.hedef.contains(id) {
                withAnimation(.easeOut(duration: 0.25)) { sabotajAsama = .bulundu(deneme: yanlis + 1) }
                sabotajBitir(bulundu: true, deneme: yanlis + 1)
            } else if yanlis == 0 {
                withAnimation(.easeOut(duration: 0.2)) { sabotajAsama = .ariyor(yanlis: 1) }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { sabotajAsama = .bulunamadi }
                sabotajBitir(bulundu: false, deneme: 2)
            }
        }
    }

    /// Seçili çip boş kutuya: etiket aynıysa yerleşir (aynı etiketli kutular birbirinin yerine geçebilir);
    /// değilse kutu kırmızı sallanır, çip şeride döner, hata +1.
    private func insaYerlestir(_ kutu: String) {
        guard durum.gizli.contains(kutu), let cipId = seciliCip, let cip = cipler.first(where: { $0.id == cipId }) else { return }
        let hedefEtiket = levha.dugumler.first { $0.id == kutu }?.etiket
        if cip.etiket == hedefEtiket {
            withAnimation(.easeOut(duration: 0.25)) {
                _ = yerlesen.insert(kutu)
                cipler.removeAll { $0.id == cipId }
                seciliCip = nil
            }
            if insaBitti {
                DurumServisi.insaKaydet(levha: levha, hata: insaHata, toplam: insaHedefler.count,
                                        sure: Date.now.timeIntervalSince(insaBaslangic), context)
                bildir(.insaBitti(levhaId: levha.id))
            }
        } else {
            insaHata += 1
            ilkDenemeKacan.insert(kutu)
            hataliMaske = kutu
            seciliCip = nil
            withAnimation(.linear(duration: 0.45)) { sallama += 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(650))
                if hataliMaske == kutu { withAnimation(.easeOut(duration: 0.2)) { hataliMaske = nil } }
            }
        }
    }

    private func sabotajBitir(bulundu: Bool, deneme: Int) {
        guard let s = senaryo else { return }
        DurumServisi.sabotajKaydet(levha: levha, tip: s.tip, bulundu: bulundu, deneme: deneme, context)
        bildir(.sabotajBitti(levhaId: levha.id, bulundu: bulundu))
    }

    private func kaydet(bilemedikler: Set<String>) {
        DurumServisi.ortmeKaydet(levha: levha, hedefler: hedefler, bilemedikler: bilemedikler, context)
        withAnimation(.easeOut(duration: 0.25)) {
            asama = .kaydedildi(bildim: hedefler.count - bilemedikler.count, bilemedim: bilemedikler.count)
        }
        bildir(.ortmeKaydedildi(levhaId: levha.id))
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
        hedefleriSec()
        sabotajKur()
        insaKur()
    }

    // MARK: - Paneller

    private static let katmanAdlari: [LevhaTipi: [String]] = [
        .algoritma: ["Düğümler", "Bağlantılar", "TUS vurguları", "Notlar"],
        .yolak: ["Maddeler", "Bağlantılar", "TUS vurguları", "Notlar"],
        .agac: ["Kök ve 1. seviye", "Alt seviyeler", "TUS vurguları", "Notlar"],
        .matris: ["Başlıklar", "Hücreler", "TUS vurguları", "Notlar"],
        .sayi_cetveli: ["İşaretler", "Değerler", "TUS vurguları", "Notlar"],
        .zaman_cizelgesi: ["Eksen ve şeritler", "Olaylar", "TUS vurguları", "Notlar"],
        .vucut_haritasi: ["Silüet", "İşaretler", "TUS vurguları", "Notlar"],
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
            NotIcerigi(dugum: d)
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

    @ViewBuilder
    private var sabotajPaneli: some View {
        HStack(spacing: 8) {
            PanelBasligi(ust: "SABOTAJ", alt: senaryo.map { $0.yazilmis ? "yazılmış" : "üretilmiş" })
            Spacer()
            if case .ariyor(let y) = sabotajAsama {
                Text("Hak \(2 - y)/2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.ikincil)
            }
        }
        if senaryo == nil {
            Text("Bu levha için sabotaj üretilemedi.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        } else {
            switch sabotajAsama {
            case .ariyor(let yanlis):
                if yanlis == 0 {
                    Text("Bu levhada bir hata var. Yanlış düğüme dokun.")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                } else {
                    Label("Bu düğüm doğru. Bir hakkın daha var.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(RenkSeti.sari.yazi)
                }
            case .bulundu(let deneme):
                Label(deneme == 1 ? "Buldun!" : "Buldun (2. deneme)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(RenkSeti.yesil.yazi)
                sabotajSonu
            case .bulunamadi:
                Label("Bulamadın — hata yeşil halkada", systemImage: "xmark.octagon.fill")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(RenkSeti.kirmizi.yazi)
                sabotajSonu
            }
        }
    }

    @ViewBuilder
    private var insaPaneli: some View {
        HStack(spacing: 8) {
            PanelBasligi(ust: "İNŞA", alt: "Yerleşen \(yerlesen.count)/\(insaHedefler.count)")
            Spacer()
            Text("Hata \(insaHata)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(insaHata > 0 ? RenkSeti.kirmizi.yazi : Tema.ikincil)
        }
        if insaHedefler.isEmpty {
            Text("Bu levhada inşa sırası yok.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
        } else if insaBitti {
            let ilk = insaHedefler.count - ilkDenemeKacan.count
            Label("\(ilk)/\(insaHedefler.count) ilk denemede · hata \(insaHata)", systemImage: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ilk == insaHedefler.count ? RenkSeti.yesil.yazi : RenkSeti.sari.yazi)
            Spacer(minLength: 0)
            PanelDugmesi(baslik: "Baştan dene", renk: .gri, dolu: false) {
                insaDeneme += 1
                withAnimation(.easeOut(duration: 0.25)) { insaKur() }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(cipler) { c in
                        let secildi = seciliCip == c.id
                        let renk = RenkSeti.ad(c.renk)
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { seciliCip = secildi ? nil : c.id }
                        } label: {
                            Text(c.etiket)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(secildi ? Color.white : renk.yazi)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .background(secildi ? renk.kenar : renk.zemin, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(renk.kenar, lineWidth: 1.5))
                                .scaleEffect(secildi ? 1.04 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(secildi ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            Text(seciliCip == nil ? "Bir çip seç, sonra boş kutuya dokun." : "Şimdi boş kutuya dokun.")
                .font(.system(size: 12.5))
                .foregroundStyle(Tema.ikincil)
        }
    }

    @ViewBuilder
    private var sabotajSonu: some View {
        if let s = senaryo {
            Text(s.dogrusu)
                .font(.system(size: 13))
                .foregroundStyle(Tema.metin)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        Spacer(minLength: 0)
        Button("Baştan dene (yeni sabotaj)") {
            sabotajDeneme += 1
            withAnimation(.easeOut(duration: 0.25)) { sabotajKur() }
        }
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(Tema.ikincil)
    }
}

// MARK: - Parçalar

/// Paket notu, altında kullanıcının "Notum" kayıtları (paket güncellemesinde silinmez).
struct NotIcerigi: View {
    let dugum: Dugum
    @Query private var notlar: [DugumNotu]

    init(dugum: Dugum) {
        self.dugum = dugum
        let (l, d) = (dugum.levha?.id ?? "", dugum.id)
        _notlar = Query(filter: #Predicate<DugumNotu> { $0.levhaId == l && $0.dugumId == d }, sort: \.tarih)
    }

    var body: some View {
        Text(dugum.etiket)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(RenkSeti.ad(dugum.renk).yazi)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(dugum.not.isEmpty ? "Bu düğüm için not yok." : dugum.not)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.metin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !notlar.isEmpty {
                    Text("NOTUM")
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(RenkSeti.mavi.yazi)
                        .padding(.top, 2)
                    ForEach(notlar) { n in
                        Text(n.metin)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Tema.metin)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RenkSeti.mavi.zemin, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .scrollIndicators(.visible)
    }
}

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
    var izinli: [LevhaModu] = LevhaModu.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(izinli) { m in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mod = m }
                } label: {
                    Text(m.ad)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(mod == m ? Color.white : Tema.metin)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(mod == m ? Tema.metin : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mod == m ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
    }
}

struct NotPaneli<Icerik: View>: View {
    var kenar: Color?
    @ViewBuilder var icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { icerik }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 156, alignment: .topLeading)
            .levhaKarti()
            .overlay {
                if let kenar {
                    RoundedRectangle(cornerRadius: Tema.kartKose, style: .continuous).strokeBorder(kenar, lineWidth: 2)
                }
            }
            .animation(.easeOut(duration: 0.2), value: kenar)
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
