import SwiftUI
import SwiftData

/// Ayarlar › "Soru kırma açık" (varsayılan açık).
enum SoruKirmaAyari {
    static let anahtar = "soruKirmaAcik"
    /// 10 sn; `-kirmaSuresi <sn>` başlatma argümanıyla değişir (simülatörde elle test için).
    static var sure: Double {
        let d = UserDefaults.standard.double(forKey: "kirmaSuresi")
        return d > 0 ? d : 10
    }
    static var acik: Bool { UserDefaults.standard.object(forKey: anahtar) as? Bool ?? true }
}

/// Şıklar kilitliyken üstte: 10 saniyelik halka + 12 kalıp çipi.
struct KirmaPaneli: View {
    let kalan: Double
    @Binding var kalip: KalipTipi?
    let ipucuGerekli: Bool
    let ipucuSecildi: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Tema.kartKenar, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: kalan / SoruKirmaAyari.sure)
                        .stroke(kalan > 3 ? Tema.metin : RenkSeti.kirmizi.kenar, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: kalan)
                    Text("\(Int(kalan.rounded(.up)))")
                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Tema.metin)
                }
                .frame(width: 36, height: 36)
                .accessibilityLabel("Kalan \(Int(kalan.rounded(.up))) saniye")
                VStack(alignment: .leading, spacing: 2) {
                    Text("SORUYU KIR").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(Tema.ikincil)
                    Text(ipucuGerekli ? "Kalıbı seç, kökte belirleyici ipucuna dokun." : "Kalıbı seç.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Adim(tamam: kalip != nil, ad: "kalıp")
                    if ipucuGerekli { Adim(tamam: ipucuSecildi, ad: "ipucu") }
                }
            }
            AkisDizilimi(bosluk: 5) {
                ForEach(KalipTipi.allCases, id: \.self) { k in
                    let secili = kalip == k
                    Button { kalip = secili ? nil : k } label: {
                        Text(k.ad)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secili ? Color.white : Tema.metin)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 30)
                            .background(secili ? Tema.metin : Color.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(Tema.kartKenar, lineWidth: secili ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(secili ? .isSelected : [])
                }
            }
        }
        .padding(12)
        .levhaKarti()
    }

    private struct Adim: View {
        let tamam: Bool
        let ad: String
        var body: some View {
            Label(ad, systemImage: tamam ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tamam ? RenkSeti.yesil.yazi : Tema.ikincil)
        }
    }
}

/// Kök metni; ipucu metinleri altı çizili ve dokunulabilir (bağlantı olarak). Cevaptan sonra ipuçları renklenir:
/// yanıltıcı kırmızı, belirleyici yeşil.
struct KokMetni: View {
    let kok: String
    let ipuclari: [IpucuJSON]
    var dokunulabilir = false
    var secili: Int?
    var renkli = false
    var vurgu: Range<String.Index>?
    var sec: (Int) -> Void = { _ in }

    var body: some View {
        Text(metin)
            .font(.system(size: 16))
            .foregroundStyle(Tema.metin)
            .tint(Tema.metin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "ipucu", let i = Int(url.host() ?? "") { sec(i) }
                return .handled
            })
    }

    private var metin: AttributedString {
        var a = AttributedString(kok)
        if let vurgu, let r = Range(NSRange(vurgu, in: kok), in: a) {
            a[r].backgroundColor = RenkSeti.sari.zemin
            a[r].foregroundColor = RenkSeti.sari.yazi
        }
        for (i, ip) in ipuclari.enumerated() {
            guard let r0 = kok.range(of: ip.metin), let r = Range(NSRange(r0, in: kok), in: a) else { continue }
            if dokunulabilir {
                a[r].link = URL(string: "ipucu://\(i)")
                a[r].underlineStyle = Text.LineStyle.single
            }
            if secili == i {
                a[r].backgroundColor = renkli && ip.yanilticiMi ? RenkSeti.kirmizi.zemin : RenkSeti.mavi.zemin
                a[r].font = .system(size: 16, weight: .semibold)
            } else if renkli {
                a[r].backgroundColor = ip.yanilticiMi ? RenkSeti.kirmizi.zemin.opacity(0.7) : RenkSeti.yesil.zemin
            }
        }
        return a
    }
}

/// Geri bildirim kartındaki kırma özeti: kalıp, ipucu, sınıf.
struct KirmaOzeti: View {
    let soru: Soru
    let olay: (kalip: KalipTipi?, ipucu: Int?)
    let dogru: Bool

    var body: some View {
        let gercek = soru.kalipTipi
        let ipuclari = soru.ipuclari
        let ringa = olay.ipucu.map { ipuclari.indices.contains($0) && ipuclari[$0].yanilticiMi } ?? false
        let sinif = KirmaSinifi.sinifla(kalipTahmini: olay.kalip?.rawValue, gercekKalip: gercek?.rawValue, cevapDogru: dogru)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("KIRMA").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(Tema.ikincil)
                if let sinif { Rozet(metin: sinif.ad, renk: sinif == .bilgiEksigi ? .sari : .kirmizi) }
                if ringa { Rozet(metin: "Ringaya kandın", renk: .kirmizi) }
            }
            let kalipDogru = olay.kalip != nil && olay.kalip == gercek
            Label {
                Text("Kalıp: \(olay.kalip?.ad ?? "seçilmedi")" + (kalipDogru ? "" : " · doğrusu \(gercek?.ad ?? "—")"))
            } icon: {
                Image(systemName: kalipDogru ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(kalipDogru ? RenkSeti.yesil.kenar : RenkSeti.kirmizi.kenar)
            }
            if !ipuclari.isEmpty {
                Label {
                    if let i = olay.ipucu, ipuclari.indices.contains(i) {
                        Text("İpucu: «\(ipuclari[i].metin)» · " + (ringa ? "yanıltıcıydı" : "ağırlık \(ipuclari[i].agirlik ?? 0)/3"))
                    } else {
                        Text("İpucu: seçilmedi")
                    }
                } icon: {
                    Image(systemName: ringa || olay.ipucu == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(ringa || olay.ipucu == nil ? RenkSeti.kirmizi.kenar : RenkSeti.yesil.kenar)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Tema.metin)
    }
}

// MARK: - Kırılım

struct KirilimGosterimi: Identifiable, Hashable {
    let id = UUID()
    let soruId: String
    let indeks: Int
}

/// Kırılım: değişen ipucu sarı vurgulu yeni kök, yeni doğru şık; levhada yol yeni düğüme kayar. Salt okuma.
struct KirilimView: View {
    let soru: Soru
    let kirilim: KirilimJSON
    let levha: Levha?

    @State private var halkalar: [String: HalkaTuru] = [:]
    @State private var kalin: Set<String> = []
    @State private var oynatma = 0
    private let harfler = ["A", "B", "C", "D", "E"]

    private var ipucu: IpucuJSON? { soru.ipuclari.indices.contains(kirilim.ipucu) ? soru.ipuclari[kirilim.ipucu] : nil }
    private var yeniKok: (metin: String, aralik: Range<String.Index>)? {
        ipucu.flatMap { KirmaSinifi.kirilimKoku(kok: soru.kok, eski: $0.metin, yeni: kirilim.yeni_metin) }
    }
    private var eskiYol: [String] { soru.aciklama_yolu.isEmpty ? soru.dugumler : soru.aciklama_yolu }
    /// Yeni doğru şıkkın düğümü: çeldirici eşlemesinden, yoksa değişen ipucunun düğümünden.
    private var yeniDugum: String? { soru.celdiriciler[kirilim.yeni_dogru] ?? ipucu?.dugum }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("KIRILIM").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(Tema.ikincil)
                        if let ipucu {
                            Text("«\(ipucu.metin)» → «\(kirilim.yeni_metin)»")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RenkSeti.sari.yazi)
                                .lineLimit(2)
                        }
                    }
                    if let y = yeniKok {
                        KokMetni(kok: y.metin, ipuclari: [], vurgu: y.aralik)
                    }
                    let yeniDogru = min(max(kirilim.yeni_dogru, 0), soru.secenekler.count - 1)
                    Label("Yeni doğru: \(harfler[min(yeniDogru, 4)]) · \(soru.secenekler[yeniDogru])", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RenkSeti.yesil.yazi)
                    Text("Önceki doğru: \(harfler[min(soru.dogru, 4)]) · \(soru.secenekler[soru.dogru])")
                        .font(.system(size: 12.5))
                        .strikethrough()
                        .foregroundStyle(Tema.ikincil)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 230)
            .levhaKarti()

            if let levha {
                LevhaView(levha: levha,
                          mode: LevhaGorunumDurumu(mod: .kesif, katman: LevhaGorunumDurumu.katmanSayisi,
                                                   halkalar: halkalar, kalinBaglantilar: kalin))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .levhaKarti()
            }

            HStack(alignment: .top) {
                Text(kirilim.aciklama ?? "Kırılımın açıklaması yok.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.metin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Tekrar oynat") { oynatma += 1 }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Tema.ikincil)
            }
            .padding(12)
            .levhaKarti()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Tema.arkaPlan)
        .navigationTitle("Kırılım")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: oynatma) { await oynat() }
    }

    /// Önce eski yol (koyu halkalar), sonra son durak yeni düğüme kayar (sarı → koyu).
    private func oynat() async {
        halkalar = [:]
        kalin = []
        try? await Task.sleep(for: .milliseconds(300))
        for (i, id) in eskiYol.enumerated() {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) {
                halkalar[id] = .koyu
                if i > 0 { kalin.insert("\(eskiYol[i - 1])>\(id)") }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let yeni = yeniDugum, !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(600))
        let hedef = eskiYol.last
        withAnimation(.easeOut(duration: 0.35)) {
            if let hedef, hedef != yeni {
                halkalar[hedef] = nil
                if eskiYol.count > 1 { kalin.remove("\(eskiYol[eskiYol.count - 2])>\(hedef)") }
            }
            halkalar[yeni] = .sari
            if eskiYol.count > 1 { kalin.insert("\(eskiYol[eskiYol.count - 2])>\(yeni)") }
        }
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeOut(duration: 0.25)) { halkalar[yeni] = .koyu }
    }
}

// MARK: - İpucu avı

/// İpucu avında tek soru: kartlar kökteki sırayla açılır; "Tanıyı biliyorum" ile şıklar gelir.
struct IpucuAviKarti: View {
    let soru: Soru
    let ust: String
    let sonIndeks: Bool
    var cevaplandi: (Bool) -> Void
    var levhaGoster: (LevhaGosterimi) -> Void
    var sonraki: () -> Void

    @Environment(\.modelContext) private var context
    @State private var acilan = 1
    @State private var isaretli: Set<Int> = []
    @State private var tahmin = false
    @State private var secilen: Int?
    @State private var puan: Int?
    @State private var baslangic = Date.now
    private let harfler = ["A", "B", "C", "D", "E"]

    /// Kökteki sıraya dizilmiş ipuçları (gösterim sırası).
    private var kartlar: [IpucuJSON] {
        let ip = soru.ipuclari
        return IpucuPuani.kokSirasi(kok: soru.kok, metinler: ip.map(\.metin)).map { ip[$0] }
    }

    var body: some View {
        let kartlar = self.kartlar
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ust)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.ikincil)
                    .lineLimit(1)
                Spacer()
                Text("İpucu \(acilan)/\(kartlar.count)")
                    .font(.system(size: 12.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Tema.metin, in: Capsule())
            }
            Text(IpucuPuani.soruCumlesi(soru.kok))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tema.ikincil)

            if secilen == nil {
                ForEach(Array(kartlar.prefix(acilan).enumerated()), id: \.offset) { i, ip in
                    IpucuKartiGorunumu(sira: i + 1, ipucu: ip, isaretli: isaretli.contains(i), sonuc: false)
                        .onLongPressGesture(minimumDuration: 0.4) {
                            if isaretli.contains(i) { isaretli.remove(i) } else { isaretli.insert(i) }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Text("Uzun bas → yanıltıcı işaretle (doğruysa +10, değilse −10).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.ikincil)
                if !tahmin {
                    HStack(spacing: 10) {
                        PanelDugmesi(baslik: "Sonraki ipucu", renk: .gri, dolu: false) {
                            withAnimation(.easeOut(duration: 0.25)) { acilan = min(acilan + 1, kartlar.count) }
                        }
                        .disabled(acilan >= kartlar.count)
                        .opacity(acilan >= kartlar.count ? 0.45 : 1)
                        PanelDugmesi(baslik: "Tanıyı biliyorum", renk: .yesil, dolu: true) {
                            withAnimation(.easeOut(duration: 0.25)) { tahmin = true }
                        }
                    }
                } else {
                    ForEach(soru.secenekler.indices, id: \.self) { i in
                        SecenekSatiri(harf: harfler[min(i, 4)], metin: soru.secenekler[i], durum: .acik)
                            .onTapGesture { cevapla(i, kartlar) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
            } else if let secilen, let puan {
                sonucKarti(secilen: secilen, puan: puan, kartlar: kartlar)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isaretli)
        .onAppear { baslangic = .now }
    }

    private func cevapla(_ i: Int, _ kartlar: [IpucuJSON]) {
        guard secilen == nil else { return }
        let dogru = i == soru.dogru
        let yanilticilar = Set(kartlar.indices.filter { kartlar[$0].yanilticiMi })
        let p = IpucuPuani.toplam(agirliklar: kartlar.map { $0.agirlik ?? 0 }, acilan: acilan, dogru: dogru,
                                  isaretlenen: isaretli, yanilticilar: yanilticilar)
        DurumServisi.ipucuKaydet(soru: soru, secilen: i, acilan: acilan, toplam: kartlar.count, puan: p,
                                 sure: Date.now.timeIntervalSince(baslangic), context)
        withAnimation(.easeOut(duration: 0.25)) {
            secilen = i
            puan = p
        }
        cevaplandi(dogru)
    }

    private func sonucKarti(secilen: Int, puan: Int, kartlar: [IpucuJSON]) -> some View {
        let dogru = secilen == soru.dogru
        let yanilticilar = Set(kartlar.indices.filter { kartlar[$0].yanilticiMi })
        let temel = IpucuPuani.temel(agirliklar: kartlar.map { $0.agirlik ?? 0 }, acilan: acilan, dogru: dogru)
        let ek = IpucuPuani.yanilticiPuani(isaretlenen: isaretli, yanilticilar: yanilticilar)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(puan > 0 ? "+\(puan)" : "\(puan)")
                    .font(.system(size: 32, weight: .heavy).monospacedDigit())
                    .foregroundStyle(dogru ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
                Text("puan").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.ikincil)
                Spacer()
                Text("\(acilan)/\(kartlar.count) ipucuyla").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            }
            Text(dogru ? "Doğru · erken tanı \(temel)" + (ek != 0 ? ", yanıltıcı işaretleri \(ek > 0 ? "+" : "")\(ek)" : "")
                       : "Yanlış · \(IpucuPuani.yanlisPuani)" + (ek != 0 ? ", yanıltıcı işaretleri \(ek > 0 ? "+" : "")\(ek)" : ""))
                .font(.system(size: 13))
                .foregroundStyle(Tema.metin)
            Label(dogru ? "Doğru: \(harfler[soru.dogru]) · \(soru.secenekler[soru.dogru])"
                        : "Sen: \(harfler[min(secilen, 4)]) · \(soru.secenekler[secilen]) — Doğru: \(harfler[soru.dogru]) · \(soru.secenekler[soru.dogru])",
                  systemImage: dogru ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(dogru ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
            Text("TAM VAKA").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(Tema.ikincil)
            KokMetni(kok: soru.kok, ipuclari: soru.ipuclari, renkli: true)
                .padding(12)
                .levhaKarti()
            ForEach(Array(kartlar.enumerated()), id: \.offset) { i, ip in
                IpucuKartiGorunumu(sira: i + 1, ipucu: ip, isaretli: isaretli.contains(i), sonuc: true)
            }
            Text(soru.aciklama)
                .font(.system(size: 14))
                .foregroundStyle(Tema.metin)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                PanelDugmesi(baslik: "Levhada göster", renk: .mavi, dolu: false) {
                    levhaGoster(LevhaGosterimi(levhaId: soru.levha, yol: soru.aciklama_yolu.isEmpty ? soru.dugumler : soru.aciklama_yolu,
                                               celdirici: dogru ? nil : soru.celdiriciler[secilen]))
                }
                Button(action: sonraki) {
                    Text(sonIndeks ? "Bitir" : "Sonraki")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Tema.metin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .levhaKarti()
    }
}

private struct IpucuKartiGorunumu: View {
    let sira: Int
    let ipucu: IpucuJSON
    let isaretli: Bool
    /// Cevaptan sonra: tür, ağırlık ve gerçekte yanıltıcı olup olmadığı görünür.
    let sonuc: Bool

    var body: some View {
        let ringa = sonuc && ipucu.yanilticiMi
        HStack(alignment: .top, spacing: 10) {
            Text("\(sira)")
                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                .foregroundStyle(Tema.ikincil)
                .frame(width: 22, height: 22)
                .background(Tema.maskeZemin, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(ipucu.metin)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Tema.metin)
                    .fixedSize(horizontal: false, vertical: true)
                if sonuc {
                    Text("\(ipucu.ipucuTuru?.ad ?? ipucu.tur) · " + (ipucu.yanilticiMi ? "yanıltıcı" : "ağırlık \(ipucu.agirlik ?? 0)/3"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(ringa ? RenkSeti.kirmizi.yazi : Tema.ikincil)
                }
            }
            Spacer(minLength: 0)
            if isaretli {
                Label("yanıltıcı", systemImage: "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RenkSeti.kirmizi.yazi)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ringa ? RenkSeti.kirmizi.zemin : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isaretli ? RenkSeti.kirmizi.kenar : Tema.kartKenar, style: StrokeStyle(lineWidth: isaretli ? 1.5 : 1, dash: isaretli ? [5, 3] : [])))
        .contentShape(Rectangle())
    }
}
