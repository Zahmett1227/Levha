import SwiftUI
import SwiftData

/// Mini sınav soru seçimi: ders kotaları sınav tablosuna oranlı, ders içinde sorulabilirlik tabakalarına göre;
/// son 30 günde çözülmüş soru ancak başka soru kalmazsa gelir.
@MainActor
enum MiniSinavSecici {
    nonisolated static let soruBasinaSaniye = 68.0   // TUS: 240 soru / 270 dk
    nonisolated static let sayilar = [10, 20, 30, 60]

    static func sec(dersler: Set<String>, sayi: Int, tohum: String, _ context: ModelContext) -> [String] {
        let havuz = ((try? context.fetch(FetchDescriptor<Soru>())) ?? []).filter { s in s.ders.map(dersler.contains) ?? false }
        let sinir = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let yakinOlaylar = (try? context.fetch(FetchDescriptor<SoruOlayi>(predicate: #Predicate { $0.tarih >= sinir }))) ?? []
        let yakin = Set(yakinOlaylar.map(\.soruGlobalId))
        var rng = TohumluUretec(tohum: tohum)
        let dersHavuzu = Dictionary(grouping: havuz.shuffled(using: &rng)) { $0.ders ?? "" }

        // Ders kotaları; eksik kalan kota havuzu olan derslere yeniden dağılır.
        var kota = dagit(min(sayi, havuz.count), dersHavuzu.keys.sorted().map { ($0, Double(SinavAyarlari.soruSayisi($0))) })
        for _ in 0..<5 {
            let tasma = kota.reduce(0) { $0 + max(0, $1.value - (dersHavuzu[$1.key]?.count ?? 0)) }
            guard tasma > 0 else { break }
            for (d, k) in kota { kota[d] = min(k, dersHavuzu[d]?.count ?? 0) }
            let bos = dersHavuzu.keys.filter { (kota[$0] ?? 0) < (dersHavuzu[$0]?.count ?? 0) }.sorted()
            for (d, ek) in dagit(tasma, bos.map { ($0, Double(SinavAyarlari.soruSayisi($0))) }) { kota[d, default: 0] += ek }
        }

        var secilen: [Soru] = []
        for (ders, k) in kota.sorted(by: { $0.key < $1.key }) where k > 0 {
            let sorular = dersHavuzu[ders] ?? []
            // Yakın zamanda çözülmemişler önce.
            let sirali = sorular.filter { !yakin.contains($0.kimlik) } + sorular.filter { yakin.contains($0.kimlik) }
            let tabakaKota = dagit(k, NetHesabi.tabakaPaylari.map { ("\($0.key)", $0.value) })
            var alinan: [Soru] = []
            for s in sirali {
                let t = "\(min(5, max(1, s.sorulabilirlik ?? 3)))"
                if (tabakaKota[t] ?? 0) > alinan.filter({ "\(min(5, max(1, $0.sorulabilirlik ?? 3)))" == t }).count { alinan.append(s) }
            }
            // Tabakası dolmayan kota en çok sorulabilir, yakın zamanda çözülmemiş sorularla dolar.
            for s in sirali.sorted(by: { ($0.sorulabilirlik ?? 3) > ($1.sorulabilirlik ?? 3) }) where alinan.count < k {
                if !alinan.contains(where: { $0.kimlik == s.kimlik }) { alinan.append(s) }
            }
            secilen += alinan.prefix(k)
        }
        return secilen.shuffled(using: &rng).map(\.kimlik)
    }

    /// En büyük kalan yöntemiyle `toplam`ı ağırlıklara böler.
    static func dagit(_ toplam: Int, _ agirliklar: [(String, Double)]) -> [String: Int] {
        let w = agirliklar.filter { $0.1 > 0 }
        let t = w.reduce(0) { $0 + $1.1 }
        guard toplam > 0, t > 0 else { return [:] }
        var sonuc = Dictionary(uniqueKeysWithValues: w.map { ($0.0, Int((Double(toplam) * $0.1 / t).rounded(.down))) })
        let kalan = toplam - sonuc.values.reduce(0, +)
        for (ad, _) in w.sorted(by: { (Double(toplam) * $0.1 / t).truncatingRemainder(dividingBy: 1) > (Double(toplam) * $1.1 / t).truncatingRemainder(dividingBy: 1) }).prefix(kalan) {
            sonuc[ad, default: 0] += 1
        }
        return sonuc
    }
}

// MARK: - Kurulum

struct MiniSinavKurulumu: Identifiable, Hashable {
    let id = UUID()
    let soruIdleri: [String]
    let dersler: [String]
    var sureSaniye: Double { Double(soruIdleri.count) * MiniSinavSecici.soruBasinaSaniye }
}

struct MiniSinavKurulumView: View {
    let baslat: (MiniSinavKurulumu) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var sorular: [Soru]
    @State private var secili: Set<String> = []
    @State private var sayi = 30
    @State private var hazir = false

    private var dersler: [String] { Array(Set(sorular.compactMap(\.ders))).sorted { SinavAyarlari.siraIndeksi($0) < SinavAyarlari.siraIndeksi($1) } }
    private var havuz: Int { sorular.filter { $0.ders.map(secili.contains) ?? false }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if dersler.isEmpty {
                        Text("Henüz soru yok. İçerik sekmesinden paket içe aktar.").foregroundStyle(Tema.ikincil)
                    }
                    ForEach(dersler, id: \.self) { d in
                        Toggle(isOn: Binding(get: { secili.contains(d) }, set: { if $0 { secili.insert(d) } else { secili.remove(d) } })) {
                            HStack {
                                Text(d)
                                Spacer()
                                Text("\(sorular.filter { $0.ders == d }.count) soru · tabloda \(SinavAyarlari.soruSayisi(d))")
                                    .font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                            }
                        }
                        .tint(Tema.metin)
                    }
                } header: {
                    Text("Dersler")
                } footer: {
                    Text("Dağılım Ayarlar'daki sınav tablosuna oranlı; ders içinde sorulabilirlik tabakalarına göre (5: %35, 4: %30, 3: %20, 2: %10, 1: %5). Son 30 günde çözdüğün sorular ancak yetmezse gelir.")
                }
                Section {
                    Picker("Soru sayısı", selection: $sayi) {
                        ForEach(MiniSinavSecici.sayilar, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Süre", value: "\(Int((Double(min(sayi, havuz)) * MiniSinavSecici.soruBasinaSaniye / 60).rounded())) dk")
                    if havuz < sayi {
                        Label("Seçili derslerde yalnız \(havuz) soru var; sınav \(havuz) soru olur.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(RenkSeti.sari.yazi)
                    }
                } header: {
                    Text("Sınav")
                } footer: {
                    Text("Soru başına 68 sn (TUS: 240 soru / 270 dk). Sınav bitene kadar geri bildirim yok; soru kırma ve İpucu avı kapalı.")
                }
                Section {
                    Button {
                        let idler = MiniSinavSecici.sec(dersler: secili, sayi: sayi, tohum: "sinav|\(Date.now.timeIntervalSince1970)", context)
                        dismiss()
                        baslat(MiniSinavKurulumu(soruIdleri: idler, dersler: secili.sorted()))
                    } label: {
                        Label("Sınavı başlat", systemImage: "stopwatch")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(havuz == 0)
                }
            }
            .navigationTitle("Mini sınav")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .onAppear {
                guard !hazir else { return }
                hazir = true
                secili = Set(dersler)
            }
        }
    }
}

// MARK: - Sınav

struct MiniSinavView: View {
    let kurulum: MiniSinavKurulumu
    var kapat: () -> Void

    @Environment(\.modelContext) private var context
    @State private var sorular: [Soru] = []
    @State private var cevaplar: [Cevap] = []
    @State private var indeks = 0
    @State private var baslangic = Date.now
    @State private var soruBaslangic = Date.now
    @State private var kalan: Double = 0
    @State private var bitirSor = false
    @State private var sonuc: SinavOlayi?
    @State private var yuklendi = false

    struct Cevap {
        var secilen: Int?
        var bos = false
        var isaretli = false
        var guven: Int?
        var sure: Double = 0
    }

    private let harfler = ["A", "B", "C", "D", "E"]

    var body: some View {
        NavigationStack {
            Group {
                if let sonuc {
                    MiniSinavSonucView(olay: sonuc, sorular: sorular)
                } else if !yuklendi {
                    ProgressView()
                } else if sorular.isEmpty {
                    ContentUnavailableView("Soru yok", systemImage: "questionmark.circle", description: Text("Seçili derslerde soru bulunamadı."))
                } else {
                    sinavEkrani
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tema.arkaPlan)
            .navigationTitle(sonuc == nil ? "Mini sınav" : "Sınav sonucu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sonuc == nil {
                    ToolbarItem(placement: .principal) {
                        Text(sureMetni)
                            .font(.system(size: 16, weight: .heavy).monospacedDigit())
                            .foregroundStyle(kalan < 300 ? RenkSeti.kirmizi.yazi : Tema.metin)
                            .accessibilityLabel("Kalan süre \(sureMetni)")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Bitir") { bitirSor = true } }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Kapat", action: kapat) }
                }
            }
            .alert("Sınavı bitir?", isPresented: $bitirSor) {
                Button("Bitir", role: .destructive, action: bitir)
                Button("Devam", role: .cancel) {}
            } message: {
                let bos = cevaplar.filter { $0.secilen == nil }.count
                Text(bos > 0 ? "\(bos) soru cevapsız; boş sayılacak." : "Tüm sorular cevaplandı.")
            }
        }
        .onAppear(perform: yukle)
        .task(id: yuklendi) { await sayac() }
    }

    private var sureMetni: String {
        let s = Int(max(0, kalan).rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func yukle() {
        guard !yuklendi else { return }
        let hepsi = (try? context.fetch(FetchDescriptor<Soru>())) ?? []
        let sozluk = Dictionary(hepsi.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        sorular = kurulum.soruIdleri.compactMap { sozluk[$0] }
        cevaplar = Array(repeating: Cevap(), count: sorular.count)
        baslangic = .now
        soruBaslangic = .now
        kalan = Double(sorular.count) * MiniSinavSecici.soruBasinaSaniye
        yuklendi = true
    }

    private func sayac() async {
        guard yuklendi, !sorular.isEmpty else { return }
        let toplam = Double(sorular.count) * MiniSinavSecici.soruBasinaSaniye
        while !Task.isCancelled && sonuc == nil {
            kalan = toplam - Date.now.timeIntervalSince(baslangic)
            if kalan <= 0 {
                bitir()
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: Ekran

    private var sinavEkrani: some View {
        let s = sorular[indeks]
        return VStack(spacing: 0) {
            numaraSeridi
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Soru \(indeks + 1)/\(sorular.count) · \(s.ders ?? "")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.ikincil)
                        Spacer()
                        if cevaplar[indeks].isaretli { Rozet(metin: "işaretli", renk: .sari) }
                        if cevaplar[indeks].bos { Rozet(metin: "boş", renk: .gri) }
                    }
                    Text(s.kok)
                        .font(.system(size: 16))
                        .foregroundStyle(Tema.metin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .levhaKarti()
                    SecmeliGuven(guven: $cevaplar[indeks].guven)
                    ForEach(s.secenekler.indices, id: \.self) { i in
                        let secildi = cevaplar[indeks].secilen == i
                        Button {
                            cevaplar[indeks].secilen = secildi ? nil : i
                            cevaplar[indeks].bos = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(harfler[min(i, 4)])
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(secildi ? Color.white : Tema.metin)
                                    .frame(width: 28, height: 28)
                                    .background(secildi ? Tema.metin : Tema.maskeZemin, in: Circle())
                                Text(s.secenekler[i])
                                    .font(.system(size: 15, weight: secildi ? .semibold : .regular))
                                    .foregroundStyle(Tema.metin)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 52)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(secildi ? Tema.metin : Tema.kartKenar, lineWidth: secildi ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(secildi ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            altCubuk
        }
        .sensoryFeedback(.selection, trigger: indeks)
    }

    private var numaraSeridi: some View {
        ScrollViewReader { kaydirici in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(cevaplar.indices, id: \.self) { i in
                        NumaraDairesi(no: i + 1, cevap: cevaplar[i], simdiki: i == indeks)
                            .id(i)
                            .onTapGesture { git(i) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background(Color.white)
            .overlay(alignment: .bottom) { Tema.kartKenar.frame(height: 1) }
            .onChange(of: indeks) { withAnimation { kaydirici.scrollTo(indeks, anchor: .center) } }
        }
    }

    private var altCubuk: some View {
        HStack(spacing: 8) {
            Button { git(indeks - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 42) }
                .disabled(indeks == 0)
            Button {
                cevaplar[indeks].secilen = nil
                cevaplar[indeks].bos = true
                if indeks + 1 < sorular.count { git(indeks + 1) }
            } label: {
                Text("Boş bırak").font(.system(size: 14.5, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            Button { cevaplar[indeks].isaretli.toggle() } label: {
                Label(cevaplar[indeks].isaretli ? "İşaretli" : "İşaretle", systemImage: cevaplar[indeks].isaretli ? "flag.fill" : "flag")
                    .font(.system(size: 14.5, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(cevaplar[indeks].isaretli ? RenkSeti.sari.kenar : Tema.metin)
            Button { indeks + 1 < sorular.count ? git(indeks + 1) : (bitirSor = true) } label: {
                Image(systemName: indeks + 1 < sorular.count ? "chevron.right" : "checkmark").frame(width: 44, height: 42)
            }
        }
        .tint(Tema.metin)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(alignment: .top) { Tema.kartKenar.frame(height: 1) }
    }

    private func git(_ i: Int) {
        guard cevaplar.indices.contains(i), i != indeks else { return }
        cevaplar[indeks].sure += Date.now.timeIntervalSince(soruBaslangic)
        soruBaslangic = .now
        withAnimation(.easeOut(duration: 0.15)) { indeks = i }
    }

    // MARK: Bitiş

    private func bitir() {
        guard sonuc == nil, !sorular.isEmpty else { return }
        cevaplar[indeks].sure += Date.now.timeIntervalSince(soruBaslangic)
        let bitis = Date.now
        let ceza = SinavAyarlari.ceza
        // Aynı günkü tahmin: sınav öncesi 14 günün cevapları, bu sınavın soru sayısı için.
        let sinir = Calendar.current.date(byAdding: .day, value: -14, to: baslangic) ?? baslangic
        let bas = baslangic
        let onceki = (try? context.fetch(FetchDescriptor<SoruOlayi>(predicate: #Predicate { $0.tarih >= sinir && $0.tarih < bas }))) ?? []
        let hepsi = Dictionary(((try? context.fetch(FetchDescriptor<Soru>())) ?? []).map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        let tahmin = NetHesabi.tahmin(cevaplar: onceki.map { ((hepsi[$0.soruGlobalId]?.sorulabilirlik) ?? 3, $0.dogruMu) },
                                      N: sorular.count, ceza: ceza)

        var dogru = 0, yanlis = 0
        var detay: [SinavSorusu] = []
        for (s, c) in zip(sorular, cevaplar) {
            detay.append(SinavSorusu(soruId: s.kimlik, secilen: c.secilen, dogru: s.dogru, guven: c.guven, isaretli: c.isaretli))
            guard let secilen = c.secilen else { continue }
            if secilen == s.dogru { dogru += 1 } else { yanlis += 1 }
            DurumServisi.soruKaydet(soru: s, secilen: secilen, guven: c.guven, sure: c.sure, baglam: "sinav", tarih: bitis, toplu: true, context)
        }
        let olay = SinavOlayi(tarih: bitis, soruSayisi: sorular.count, net: TahminPolitikasi.net(dogru: dogru, yanlis: yanlis, ceza: ceza),
                              dogru: dogru, yanlis: yanlis, bos: sorular.count - dogru - yanlis,
                              sureSaniye: bitis.timeIntervalSince(baslangic), dersler: kurulum.dersler)
        if tahmin.n > 0 {
            olay.tahminBeklenen = tahmin.beklenen
            olay.tahminAlt = tahmin.alt
            olay.tahminUst = tahmin.ust
            olay.tahminN = tahmin.n
        }
        olay.detay = try? JSONEncoder().encode(detay)
        context.insert(olay)
        try? context.save()
        WidgetYazici.yaz(context)
        OlayDefteri.degisti()
        withAnimation(.easeOut(duration: 0.25)) { sonuc = olay }
    }
}

/// Güven işareti; sınavda zorunlu değil (ikinci dokunuş kaldırır).
struct SecmeliGuven: View {
    @Binding var guven: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text("Güven")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Tema.ikincil)
            ForEach([1, 2, 3], id: \.self) { g in
                Button { guven = guven == g ? nil : g } label: {
                    Text(GuvenSecici.adlar[g] ?? "")
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
            Text("isteğe bağlı").font(.system(size: 11)).foregroundStyle(Tema.cizgi)
        }
    }
}

/// Numara şeridindeki daire: cevaplanan dolu, boş bırakılan çizgili, işaretli sarı.
private struct NumaraDairesi: View {
    let no: Int
    let cevap: MiniSinavView.Cevap
    let simdiki: Bool

    var body: some View {
        let cevapli = cevap.secilen != nil
        // İşaretli daire sarı zeminlidir; yazı koyu kalır.
        let yazi = cevap.isaretli ? Tema.metin : (cevapli ? Color.white : Tema.metin)
        Text("\(no)")
            .font(.system(size: 12.5, weight: .bold).monospacedDigit())
            .foregroundStyle(yazi)
            .frame(width: 32, height: 32)
            .background {
                ZStack {
                    Circle().fill(cevap.isaretli ? RenkSeti.sari.zemin : (cevapli ? Tema.metin : Color.white))
                    if cevap.bos && !cevapli {
                        Cizgili().stroke(Tema.cizgi, lineWidth: 1).clipShape(Circle())
                    }
                }
            }
            .overlay(Circle().strokeBorder(cevap.isaretli ? RenkSeti.sari.kenar : Tema.kartKenar, lineWidth: cevap.isaretli ? 2 : 1))
            .overlay(Circle().strokeBorder(Tema.metin, lineWidth: simdiki ? 2.5 : 0).padding(-4))
            .overlay(alignment: .bottom) {
                if cevap.isaretli && cevapli { Circle().fill(Tema.metin).frame(width: 5, height: 5).offset(y: -4) }
            }
            .accessibilityLabel("Soru \(no)\(cevapli ? ", cevaplandı" : "")\(cevap.bos ? ", boş" : "")\(cevap.isaretli ? ", işaretli" : "")")
    }
}

private struct Cizgili: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += 6
        }
        return p
    }
}

// MARK: - Sonuç

struct MiniSinavSonucView: View {
    let olay: SinavOlayi
    let sorular: [Soru]

    @Environment(\.modelContext) private var context
    @State private var gosterim: LevhaGosterimi?
    @State private var aciklama: AciklamaGosterimi?
    @State private var tumTahmin = Sayac()
    private let harfler = ["A", "B", "C", "D", "E"]

    struct AciklamaGosterimi: Identifiable {
        let id = UUID()
        let soru: Soru
        let secilen: Int?
    }

    private var detay: [(soru: Soru, cevap: SinavSorusu)] {
        let sozluk = Dictionary(sorular.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        return olay.sorular.compactMap { c in sozluk[c.soruId].map { ($0, c) } }
    }

    var body: some View {
        let ceza = SinavAyarlari.ceza
        let d = detay
        let tahminler = d.filter { $0.cevap.guven == 3 && $0.cevap.secilen != nil }
        let tahminDogru = tahminler.filter { $0.cevap.secilen == $0.cevap.dogru }.count
        let esik = NetHesabi.tahminEsigi(ceza: ceza)
        let p = TahminPolitikasi.dogruluk(dogru: tumTahmin.d, toplam: tumTahmin.n)
        let degisim = TahminPolitikasi.bosBeklenenDegisim(bosSayisi: olay.bos, dogruluk: p, ceza: ceza)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OlcumKarti(baslik: "Net", simge: "target") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Bicim.sayi(olay.net)).font(.system(size: 40, weight: .heavy).monospacedDigit())
                        Text("/ \(olay.soruSayisi)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Tema.ikincil)
                        Spacer()
                        Text("\(Int(olay.sureSaniye / 60)) dk \(Int(olay.sureSaniye) % 60) sn").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                    }
                    HStack(spacing: 8) {
                        SayiKutusu(deger: "\(olay.dogru)", ad: "doğru")
                        SayiKutusu(deger: "\(olay.yanlis)", ad: "yanlış")
                        SayiKutusu(deger: "\(olay.bos)", ad: "boş")
                    }
                    Text("Net = doğru − yanlış × \(Bicim.sayi(ceza))").font(.system(size: 12)).foregroundStyle(Tema.ikincil)
                    if let a = olay.tahminAlt, let u = olay.tahminUst {
                        Text("Sınav öncesi tahminin: \(Bicim.sayi(a.rounded()))–\(Bicim.sayi(u.rounded())) net (n=\(olay.tahminN ?? 0)\((olay.tahminN ?? 0) < NetHesabi.enAzSoru ? ", az veri" : ""))")
                            .font(.system(size: 13)).foregroundStyle(Tema.metin)
                    }
                }

                OlcumKarti(baslik: "Tahmin politikası", simge: "dice") {
                    Text("Bu sınavda \"Tahmin\" işaretlediklerin: \(tahminDogru)/\(tahminler.count) doğru" +
                         (tahminler.isEmpty ? "" : " (%\(Int((Double(tahminDogru) / Double(tahminler.count) * 100).rounded())))") +
                         " · eşik %\(Int((esik * 100).rounded()))")
                        .font(.system(size: 13.5))
                    Text("Tüm zamanlar: \(tumTahmin.d)/\(tumTahmin.n) tahmin doğru; şansa doğru büzülmüş tahmin doğruluğun %\(Int((p * 100).rounded())).")
                        .font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                    if olay.bos > 0 {
                        Text("Boş bıraktığın \(olay.bos) soruda tahmin etseydin beklenen net değişimi: \(isaretli(degisim.beklenen)) (±\(Bicim.sayi((degisim.ss * 10).rounded() / 10)))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(degisim.beklenen > 0 ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
                        Text(p > esik ? "Doğruluğun eşiğin üstünde: emin olmadığın soruyu tahmin etmek kârlı." :
                                "Doğruluğun eşiğin altında: emin olmadığın soruyu boş bırakmak daha iyi.")
                            .font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                    } else {
                        Text("Boş soru yok.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                    }
                }

                OlcumKarti(baslik: "Döküm", simge: "list.bullet.rectangle") {
                    dokum("Ders", d.map { ($0.soru.ders ?? "—", $0.cevap) })
                    Divider()
                    dokum("Kalıp", d.map { ($0.soru.kalipTipi?.ad ?? "—", $0.cevap) })
                }

                OlcumKarti(baslik: "Sorular", simge: "checklist") {
                    ForEach(Array(d.enumerated()), id: \.offset) { i, x in
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(.system(size: 12.5, weight: .bold).monospacedDigit()).frame(width: 24)
                            durumSimgesi(x.cevap)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.soru.kalipTipi?.ad ?? "—").font(.system(size: 13, weight: .semibold))
                                Text("Doğru: \(harfler[min(x.soru.dogru, 4)]) · \(x.soru.secenekler[x.soru.dogru])")
                                    .font(.system(size: 12)).foregroundStyle(Tema.ikincil).lineLimit(1)
                            }
                            Spacer()
                            if x.soru.bagimsiz {
                                // Levhası yok: açıklama + anlatım başlığı.
                                Button("Açıklama") { aciklama = AciklamaGosterimi(soru: x.soru, secilen: x.cevap.secilen) }
                                    .font(.system(size: 12, weight: .semibold))
                                    .buttonStyle(.bordered)
                                    .tint(RenkSeti.gri.kenar)
                            } else {
                                Button("Levhada göster") {
                                    let celdirici = x.cevap.secilen.flatMap { $0 == x.soru.dogru ? nil : x.soru.celdiriciler[$0] }
                                    gosterim = LevhaGosterimi(levhaId: x.soru.levha,
                                                              yol: x.soru.aciklama_yolu.isEmpty ? x.soru.dugumler : x.soru.aciklama_yolu,
                                                              celdirici: celdirici)
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .buttonStyle(.bordered)
                                .tint(RenkSeti.mavi.kenar)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .sheet(item: $aciklama) { a in SoruAciklamasi(soru: a.soru, secilen: a.secilen) }
        .navigationDestination(item: $gosterim) { g in
            let id = g.levhaId
            if let levha = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first {
                LevhaGosterimiView(levha: levha, yol: g.yol, celdirici: g.celdirici)
            }
        }
        .onAppear {
            let hepsi = (try? context.fetch(FetchDescriptor<SoruOlayi>(predicate: #Predicate { $0.guven == 3 }))) ?? []
            tumTahmin = Sayac(d: hepsi.filter(\.dogruMu).count, n: hepsi.count)
        }
    }

    private func isaretli(_ v: Double) -> String {
        let y = (v * 10).rounded() / 10
        return y > 0 ? "+\(Bicim.sayi(y))" : (y < 0 ? "−\(Bicim.sayi(-y))" : "0")
    }

    @ViewBuilder
    private func durumSimgesi(_ c: SinavSorusu) -> some View {
        if let s = c.secilen {
            Image(systemName: s == c.dogru ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(s == c.dogru ? RenkSeti.yesil.kenar : RenkSeti.kirmizi.kenar)
        } else {
            Image(systemName: "minus.circle").foregroundStyle(Tema.cizgi)
        }
    }

    private func dokum(_ baslik: String, _ satirlar: [(String, SinavSorusu)]) -> some View {
        var sira: [String] = []
        var say: [String: (d: Int, y: Int, b: Int)] = [:]
        for (ad, c) in satirlar {
            if say[ad] == nil { sira.append(ad) }
            var e = say[ad] ?? (0, 0, 0)
            if let s = c.secilen { if s == c.dogru { e.d += 1 } else { e.y += 1 } } else { e.b += 1 }
            say[ad] = e
        }
        let ceza = SinavAyarlari.ceza
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(baslik).frame(maxWidth: .infinity, alignment: .leading)
                Text("D").frame(width: 30)
                Text("Y").frame(width: 30)
                Text("B").frame(width: 30)
                Text("net").frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(Tema.ikincil)
            ForEach(sira.sorted(), id: \.self) { ad in
                let e = say[ad] ?? (0, 0, 0)
                HStack {
                    Text(ad).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text("\(e.d)").frame(width: 30)
                    Text("\(e.y)").frame(width: 30)
                    Text("\(e.b)").frame(width: 30)
                    Text(Bicim.sayi(TahminPolitikasi.net(dogru: e.d, yanlis: e.y, ceza: ceza))).frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 13).monospacedDigit())
            }
        }
    }
}
