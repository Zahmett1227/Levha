import SwiftUI
import SwiftData

struct SoruOturumu: Identifiable, Hashable {
    let id = UUID()
    let baslik: String
    let idler: [String]
    /// Günlük Tur'un Soru bloğu mu? (bitince blok tiklenir)
    let tur: Bool
    /// Bu sorular İpucu avı formatında gelir.
    var ipucuAvi: Set<String> = []
}

/// "Soru" sekmesi: Bugünün soruları ya da konu seçerek 10/15/20 soruluk oturum.
struct SoruSekmesi: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @Query(sort: \SoruOlayi.tarih, order: .reverse) private var olaylar: [SoruOlayi]
    @State private var seciliPaket = ""
    @State private var sayi = 15
    @State private var oturum: SoruOturumu?
    @State private var tur: TurDurumu?
    @State private var oturumSayaci = 0
    @State private var sinavKurulumu = false
    @State private var sinav: MiniSinavKurulumu?
    private var yonlendirici = Yonlendirici.ortak

    var body: some View {
        NavigationStack {
            List {
                Section("Bugünün soruları") {
                    if paketler.isEmpty {
                        Label("Henüz paket yok. İçerik sekmesinden içe aktar.", systemImage: "tray")
                            .foregroundStyle(Tema.ikincil)
                    }
                    if let tur, !tur.isDeleted, tur.modelContext != nil {
                        let k = TurPlanlayici.kuyruk(tur)
                        let bitti = tur.tamamlananlar.contains(TurBlogu.soru.rawValue)
                        Button {
                            oturum = SoruOturumu(baslik: "Bugünün soruları", idler: k.soru, tur: true, ipucuAvi: Set(k.ipucuAvi ?? []))
                        } label: {
                            HStack {
                                Label("Günlük Tur · \(k.soru.count) soru" + ((k.ipucuAvi ?? []).isEmpty ? "" : " (\((k.ipucuAvi ?? []).count) İpucu avı)"),
                                      systemImage: "sun.max")
                                Spacer()
                                if bitti {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RenkSeti.yesil.kenar)
                                }
                            }
                        }
                        .disabled(k.soru.isEmpty)
                    }
                }

                Section {
                    Button {
                        sinavKurulumu = true
                    } label: {
                        Label("Mini sınav kur", systemImage: "stopwatch")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(paketler.isEmpty)
                } header: {
                    Text("Mini sınav")
                } footer: {
                    Text("Süreli, geri bildirimsiz; net ve tahmin politikası sonunda.")
                }

                Section {
                    let ipuclu = ipucluSorular
                    LabeledContent("İpucu sırası olan", value: "\(ipuclu.count) soru")
                    Button {
                        ipucuOturumuBaslat(ipuclu)
                    } label: {
                        Label("İpucu avı başlat (10 soru)", systemImage: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(ipuclu.isEmpty)
                } header: {
                    Text("İpucu avı")
                } footer: {
                    Text("İpuçları kökteki sırayla açılır; tanıyı ne kadar erken bilirsen o kadar çok puan.")
                }

                Section("Konu seç") {
                    Picker("Alt konu", selection: $seciliPaket) {
                        Text("Tümü").tag("")
                        ForEach(paketler.filter { !$0.kullaniciMi }) { p in
                            Text("\(p.bolum) › \(p.alt_konu)").tag(p.paket_id)
                        }
                        if let k = paketler.first(where: \.kullaniciMi), !k.sorular.isEmpty {
                            Text("Yazdıklarım (\(k.sorular.count))").tag(k.paket_id)
                        }
                    }
                    Picker("Soru sayısı", selection: $sayi) {
                        ForEach([10, 15, 20], id: \.self) { Text("\($0) soru").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        konuOturumuBaslat()
                    } label: {
                        Label("Başla", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(paketler.isEmpty)
                }

                Section("Son 7 gün") {
                    let son = olaylar.filter { $0.tarih >= Calendar.current.date(byAdding: .day, value: -7, to: .now)! }
                    let dogru = son.filter(\.dogruMu).count
                    LabeledContent("Çözülen", value: "\(son.count) soru")
                    LabeledContent("Doğru", value: son.isEmpty ? "—" : "%\(Int((Double(dogru) / Double(son.count) * 100).rounded()))")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.arkaPlan)
            .navigationTitle("Soru")
            .navigationDestination(item: $oturum) { o in
                SoruOturumuView(baslik: o.baslik, soruIdleri: o.idler, ipucuAviIdleri: o.ipucuAvi) {
                    if o.tur, let tur, !tur.isDeleted { TurPlanlayici.tamamla(.soru, tur, context) }
                    oturum = nil
                }
            }
            .onAppear { tur = TurPlanlayici.bugun(context) }
            .onChange(of: OlayDefteri.ortak.surum) {
                if tur == nil || tur?.isDeleted == true || tur?.modelContext == nil { tur = TurPlanlayici.bugun(context) }
            }
            .sheet(isPresented: $sinavKurulumu) {
                MiniSinavKurulumView { sinav = $0 }
            }
            .fullScreenCover(item: $sinav) { k in
                MiniSinavView(kurulum: k) { sinav = nil }
            }
            .onChange(of: yonlendirici.miniSinavIstek) { sinavKurulumu = true }
        }
    }

    private var ipucluSorular: [Soru] {
        ((try? context.fetch(FetchDescriptor<Soru>(sortBy: [SortDescriptor(\.sira)]))) ?? []).filter { !$0.ipuclari.isEmpty }
    }

    private func ipucuOturumuBaslat(_ havuz: [Soru]) {
        oturumSayaci += 1
        let idler = SoruSecici.konu(havuz, sayi: 10, tohum: "ipucu-avi|\(DurumServisi.gunAnahtari())|\(oturumSayaci)", context)
        oturum = SoruOturumu(baslik: "İpucu avı", idler: idler, tur: false, ipucuAvi: Set(idler))
    }

    private func konuOturumuBaslat() {
        let tumu = (try? context.fetch(FetchDescriptor<Soru>(sortBy: [SortDescriptor(\.sira)]))) ?? []
        let havuz = seciliPaket.isEmpty ? tumu : tumu.filter { $0.paket?.paket_id == seciliPaket }
        oturumSayaci += 1
        let idler = SoruSecici.konu(havuz, sayi: sayi, tohum: "konu|\(DurumServisi.gunAnahtari())|\(seciliPaket)|\(oturumSayaci)", context)
        let ad = paketler.first { $0.paket_id == seciliPaket }?.alt_konu ?? "Tüm konular"
        oturum = SoruOturumu(baslik: ad, idler: idler, tur: false)
    }
}

/// Levhada göster: hangi levha, hangi yol, hangi çeldirici.
struct LevhaGosterimi: Identifiable, Hashable {
    let id = UUID()
    let levhaId: String
    let yol: [String]
    let celdirici: String?
}

struct SoruOturumuView: View {
    let baslik: String
    let soruIdleri: [String]
    /// Bu id'lerdeki (ipucu sırası olan) sorular İpucu avı formatında gelir.
    var ipucuAviIdleri: Set<String> = []
    var bitince: () -> Void

    @Environment(\.modelContext) private var context
    @State private var sorular: [Soru] = []
    @State private var indeks = 0
    @State private var secilen: Int?
    @State private var baslangic = Date.now
    @State private var dogruSayisi = 0
    @State private var bitti = false
    @State private var gosterim: LevhaGosterimi?
    @State private var yuklendi = false
    /// 1 Eminim · 2 Sanırım · 3 Tahmin; seçilmezse Sanırım.
    @State private var guven = 2
    // Soru kırma
    @State private var kirmaAcikMi = SoruKirmaAyari.acik
    @State private var kirmaKalip: KalipTipi?
    @State private var kirmaIpucu: Int?
    @State private var kilitAcik = false
    @State private var kirmaSure: Double?
    @State private var kalan = SoruKirmaAyari.sure
    @State private var kirilim: KirilimGosterimi?

    var body: some View {
        Group {
            if !yuklendi {
                ProgressView()
            } else if sorular.isEmpty {
                ContentUnavailableView("Soru yok", systemImage: "questionmark.circle",
                                       description: Text("Bu seçimde soru bulunamadı."))
            } else if bitti {
                ozet
            } else {
                soruEkrani(sorular[indeks])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.arkaPlan)
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $gosterim) { g in
            if let levha = levha(g.levhaId) {
                LevhaGosterimiView(levha: levha, yol: g.yol, celdirici: g.celdirici)
            }
        }
        .navigationDestination(item: $kirilim) { k in
            if let s = sorular.first(where: { $0.kimlik == k.soruId }), s.kirilimListesi.indices.contains(k.indeks) {
                KirilimView(soru: s, kirilim: s.kirilimListesi[k.indeks], levha: levha(s.levha))
            }
        }
        .onAppear(perform: yukle)
    }

    /// Kırma bu soruda çalışıyor mu (ayar açık, henüz cevaplanmadı, kilit kapalı)?
    private var kirmaSuruyor: Bool { kirmaAcikMi && secilen == nil && !kilitAcik }

    private func ipucuAviMi(_ s: Soru) -> Bool { ipucuAviIdleri.contains(s.kimlik) && !s.ipuclari.isEmpty }

    private func yukle() {
        guard !yuklendi else { return }
        let hepsi = (try? context.fetch(FetchDescriptor<Soru>())) ?? []
        let sozluk = Dictionary(hepsi.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        sorular = soruIdleri.compactMap { sozluk[$0] }
        baslangic = .now
        yuklendi = true
    }

    private func levha(_ id: String) -> Levha? {
        try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first
    }

    private func etiket(_ dugumId: String, _ levha: Levha?) -> String {
        levha?.dugumler.first { $0.id == dugumId }?.etiket ?? dugumId
    }

    // MARK: - Soru

    @ViewBuilder
    private func soruEkrani(_ s: Soru) -> some View {
        if ipucuAviMi(s) {
            ScrollView {
                IpucuAviKarti(soru: s, ust: "Soru \(indeks + 1)/\(sorular.count) · İpucu avı",
                              sonIndeks: indeks + 1 >= sorular.count,
                              cevaplandi: { if $0 { dogruSayisi += 1 } },
                              levhaGoster: { gosterim = $0 },
                              sonraki: sonraki)
                    .padding(16)
                    .id(s.kimlik)
            }
        } else {
            normalSoru(s)
        }
    }

    private func normalSoru(_ s: Soru) -> some View {
        let l = levha(s.levha)
        return ScrollViewReader { kaydirici in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Soru \(indeks + 1)/\(sorular.count) · \(s.paket?.alt_konu ?? "")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.ikincil)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        if let l {
                            Label(l.tipAdi, systemImage: "square.grid.3x3.square")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(RenkSeti.mavi.yazi)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RenkSeti.mavi.zemin, in: Capsule())
                                .accessibilityLabel("Levha: \(l.baslik)")
                        }
                    }
                    .id("ust")

                    if kirmaSuruyor {
                        KirmaPaneli(kalan: kalan, kalip: $kirmaKalip, ipucuGerekli: !s.ipuclari.isEmpty, ipucuSecildi: kirmaIpucu != nil)
                            .transition(.opacity)
                    }

                    KokMetni(kok: s.kok, ipuclari: kirmaAcikMi ? s.ipuclari : [], dokunulabilir: kirmaSuruyor,
                             secili: kirmaIpucu, renkli: secilen != nil) { i in
                        withAnimation(.easeOut(duration: 0.15)) { kirmaIpucu = kirmaIpucu == i ? nil : i }
                        kilitKontrol(s)
                    }
                    .padding(14)
                    .levhaKarti()

                    GuvenSecici(guven: $guven)
                        .disabled(secilen != nil)
                        .opacity(secilen == nil ? 1 : 0.5)

                    VStack(spacing: 12) {
                        ForEach(s.secenekler.indices, id: \.self) { i in
                            SecenekSatiri(harf: harf(i), metin: s.secenekler[i], durum: secenekDurumu(i, s))
                                .onTapGesture { cevapla(i, s) }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .opacity(kirmaSuruyor ? 0.35 : 1)
                    .allowsHitTesting(!kirmaSuruyor)
                    .overlay {
                        if kirmaSuruyor {
                            Label("Şıklar kilitli", systemImage: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Tema.metin)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().strokeBorder(Tema.kartKenar, lineWidth: 1))
                        }
                    }

                    if let secilen {
                        geriBildirim(s, secilen: secilen, levha: l)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(16)
            }
            .onChange(of: indeks) { kaydirici.scrollTo("ust", anchor: .top) }
            .onChange(of: kirmaKalip) { kilitKontrol(s) }
            .task(id: "\(s.kimlik)|\(kirmaSuruyor)") { await sayac(s) }
        }
    }

    /// 10 saniyelik halka; süre dolunca şıklar açılır.
    private func sayac(_ s: Soru) async {
        guard kirmaSuruyor else { return }
        while !Task.isCancelled && kirmaSuruyor {
            let gecen = Date.now.timeIntervalSince(baslangic)
            kalan = max(0, SoruKirmaAyari.sure - gecen)
            if kalan <= 0 {
                kilidiAc()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Kalıp seçildi ve (ipucu sırası varsa) bir ipucu seçildiyse kilit açılır.
    private func kilitKontrol(_ s: Soru) {
        guard kirmaSuruyor, kirmaKalip != nil, s.ipuclari.isEmpty || kirmaIpucu != nil else { return }
        kilidiAc()
    }

    private func kilidiAc() {
        kirmaSure = min(Date.now.timeIntervalSince(baslangic), SoruKirmaAyari.sure)
        withAnimation(.easeOut(duration: 0.25)) { kilitAcik = true }
    }

    private func harf(_ i: Int) -> String { ["A", "B", "C", "D", "E"][min(i, 4)] }

    private func secenekDurumu(_ i: Int, _ s: Soru) -> SecenekSatiri.Durum {
        guard let secilen else { return .acik }
        if i == s.dogru { return .dogru }
        if i == secilen { return .yanlis }
        return .soluk
    }

    private func cevapla(_ i: Int, _ s: Soru) {
        guard secilen == nil else { return }
        let sure = Date.now.timeIntervalSince(baslangic)
        withAnimation(.easeOut(duration: 0.25)) { secilen = i }
        if i == s.dogru { dogruSayisi += 1 }
        let kirma = kirmaAcikMi ? DurumServisi.KirmaKaydi(kalip: kirmaKalip, ipucu: kirmaIpucu, sure: kirmaSure ?? SoruKirmaAyari.sure) : nil
        DurumServisi.soruKaydet(soru: s, secilen: i, guven: guven, sure: sure, kirma: kirma, context)
    }

    private func sonraki() {
        if indeks + 1 < sorular.count {
            withAnimation(.easeOut(duration: 0.2)) {
                indeks += 1
                secilen = nil
                guven = 2
                kirmaKalip = nil
                kirmaIpucu = nil
                kilitAcik = false
                kirmaSure = nil
                kalan = SoruKirmaAyari.sure
            }
            baslangic = .now
        } else {
            withAnimation { bitti = true }
        }
    }

    private func geriBildirim(_ s: Soru, secilen: Int, levha l: Levha?) -> some View {
        let dogru = secilen == s.dogru
        let celdirici = dogru ? nil : s.celdiriciler[secilen]
        return VStack(alignment: .leading, spacing: 10) {
            Label(dogru ? "Doğru" : "Yanlış. Doğru cevap: \(harf(s.dogru)) · \(s.secenekler[s.dogru])",
                  systemImage: dogru ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(dogru ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
            Text(s.aciklama)
                .font(.system(size: 14))
                .foregroundStyle(Tema.metin)
                .fixedSize(horizontal: false, vertical: true)
            if !s.aciklama_yolu.isEmpty {
                Text("CEVAP YOLU")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Tema.ikincil)
                CevapYolu(etiketler: s.aciklama_yolu.map { etiket($0, l) })
            }
            if let celdirici {
                Label("Burada karıştırdın: \(etiket(celdirici, l))", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(RenkSeti.sari.yazi)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RenkSeti.sari.zemin, in: RoundedRectangle(cornerRadius: 8))
            }
            if kirmaAcikMi {
                KirmaOzeti(soru: s, olay: (kirmaKalip, kirmaIpucu), dogru: dogru)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tema.arkaPlan, in: RoundedRectangle(cornerRadius: 8))
            }
            let kirilimlar = s.kirilimListesi
            if !kirilimlar.isEmpty {
                HStack(spacing: 8) {
                    ForEach(kirilimlar.indices, id: \.self) { k in
                        PanelDugmesi(baslik: kirilimlar.count == 1 ? "Kırılım" : "Kırılım \(k + 1)", renk: .sari, dolu: false) {
                            kirilim = KirilimGosterimi(soruId: s.kimlik, indeks: k)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                PanelDugmesi(baslik: "Levhada göster", renk: .mavi, dolu: false) {
                    gosterim = LevhaGosterimi(levhaId: s.levha, yol: s.aciklama_yolu.isEmpty ? s.dugumler : s.aciklama_yolu,
                                              celdirici: celdirici)
                }
                .disabled(l == nil)
                Button(action: sonraki) {
                    Text(indeks + 1 < sorular.count ? "Sonraki" : "Bitir")
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

    private var ozet: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(RenkSeti.yesil.kenar)
            Text("\(sorular.count) sorudan \(dogruSayisi) doğru")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Tema.metin)
            Text("Yanlışların düğümleri Örtme'de öne alınacak.")
                .font(.system(size: 14))
                .foregroundStyle(Tema.ikincil)
            PanelDugmesi(baslik: "Bitti", renk: .gri, dolu: false, action: bitince)
                .frame(maxWidth: 220)
        }
        .padding(24)
    }
}

/// Şıktan önce: Eminim · Sanırım · Tahmin.
struct GuvenSecici: View {
    @Binding var guven: Int
    static let adlar = [1: "Eminim", 2: "Sanırım", 3: "Tahmin"]

    var body: some View {
        HStack(spacing: 6) {
            Text("Güven")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Tema.ikincil)
            ForEach([1, 2, 3], id: \.self) { g in
                Button {
                    guven = g
                } label: {
                    Text(Self.adlar[g] ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(guven == g ? Color.white : Tema.metin)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(guven == g ? Tema.metin : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(Tema.kartKenar, lineWidth: guven == g ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(guven == g ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

struct SecenekSatiri: View {
    enum Durum { case acik, dogru, yanlis, soluk }
    let harf: String
    let metin: String
    let durum: Durum

    var body: some View {
        let renk: RenkSeti? = durum == .dogru ? .yesil : (durum == .yanlis ? .kirmizi : nil)
        HStack(alignment: .center, spacing: 12) {
            Text(harf)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(renk.map { _ in Color.white } ?? Tema.metin)
                .frame(width: 28, height: 28)
                .background(renk?.kenar ?? Tema.maskeZemin, in: Circle())
            Text(metin)
                .font(.system(size: 15, weight: renk == nil ? .regular : .semibold))
                .foregroundStyle(renk?.yazi ?? Tema.metin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if durum == .dogru { Image(systemName: "checkmark").foregroundStyle(RenkSeti.yesil.kenar) }
            if durum == .yanlis { Image(systemName: "xmark").foregroundStyle(RenkSeti.kirmizi.kenar) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(renk?.zemin ?? Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(renk?.kenar ?? Tema.kartKenar, lineWidth: renk == nil ? 1 : 1.5))
        .opacity(durum == .soluk ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

/// Düğüm etiketleri ok zinciri hâlinde, satıra sığmazsa alta kayar.
struct CevapYolu: View {
    let etiketler: [String]

    var body: some View {
        AkisDizilimi(bosluk: 4) {
            ForEach(Array(etiketler.enumerated()), id: \.offset) { i, e in
                HStack(spacing: 4) {
                    if i > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Tema.cizgi)
                    }
                    Text(e)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Tema.maskeZemin, in: Capsule())
                }
            }
        }
    }
}

/// Basit akış dizilimi (satır doldukça alta geçer).
struct AkisDizilimi: Layout {
    var bosluk: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let genislik = proposal.width ?? .infinity
        var (x, y, satirH, enGenis): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x > 0 && x + b.width > genislik {
                y += satirH + bosluk
                x = 0
                satirH = 0
            }
            x += b.width + bosluk
            satirH = max(satirH, b.height)
            enGenis = max(enGenis, x)
        }
        return CGSize(width: min(enGenis, genislik), height: y + satirH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var (x, y, satirH): (CGFloat, CGFloat, CGFloat) = (bounds.minX, bounds.minY, 0)
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + b.width > bounds.maxX {
                y += satirH + bosluk
                x = bounds.minX
                satirH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(b))
            x += b.width + bosluk
            satirH = max(satirH, b.height)
        }
    }
}

/// Levhayı Keşif'in son katmanında açar; cevap yolu düğümleri 250 ms arayla koyu halka alır,
/// aralarındaki bağlantılar kalınlaşır; yanlış seçildiyse çeldirici düğüm sarı halka alır.
struct LevhaGosterimiView: View {
    let levha: Levha
    let yol: [String]
    let celdirici: String?

    @State private var halkalar: [String: HalkaTuru] = [:]
    @State private var kalin: Set<String> = []
    @State private var secili: String?
    @State private var oynatma = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(levha.baslik)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tema.metin)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            AkildaKalanSeridi(metin: levha.akilda_kalan)
            LevhaView(levha: levha,
                      mode: LevhaGorunumDurumu(mod: .kesif, katman: LevhaGorunumDurumu.katmanSayisi, secili: secili,
                                               halkalar: halkalar, kalinBaglantilar: kalin, dokunulabilir: true)) { id in
                withAnimation(.easeOut(duration: 0.25)) { secili = secili == id ? nil : id }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .levhaKarti()
            NotPaneli {
                if let id = secili, let d = levha.dugumler.first(where: { $0.id == id }) {
                    NotIcerigi(dugum: d)
                } else {
                    HStack {
                        PanelBasligi(ust: "CEVAP YOLU", alt: nil)
                        Spacer()
                        Button("Tekrar oynat") { oynatma += 1 }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.ikincil)
                    }
                    CevapYolu(etiketler: yol.map { id in levha.dugumler.first { $0.id == id }?.etiket ?? id })
                    if let c = celdirici, let d = levha.dugumler.first(where: { $0.id == c }) {
                        Label("Karıştırdığın: \(d.etiket)", systemImage: "circle.dashed")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(RenkSeti.sari.yazi)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Tema.arkaPlan)
        .navigationTitle("Levhada göster")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: oynatma) { await oynat() }
    }

    private func oynat() async {
        halkalar = [:]
        kalin = []
        secili = nil
        try? await Task.sleep(for: .milliseconds(350))
        for (i, id) in yol.enumerated() {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) {
                halkalar[id] = .koyu
                if i > 0 { kalin.insert("\(yol[i - 1])>\(id)") }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let c = celdirici {
            withAnimation(.easeOut(duration: 0.25)) { halkalar[c] = .sari }
        }
    }
}
