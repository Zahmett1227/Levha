import SwiftUI
import SwiftData
import Charts

/// Ölçüm: İçerik · Öğrenme · Soru · Kullanım. Hepsi olay tablolarından anlık hesaplanır.
struct OlcumSekmesi: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @Query private var sorular: [Soru]
    @Query private var kazanimlar: [Kazanim]
    @Query private var durumlar: [LevhaDurumu]
    @Query(sort: \OrtmeOlayi.tarih) private var ortmeler: [OrtmeOlayi]
    @Query(sort: \SoruOlayi.tarih) private var soruOlaylari: [SoruOlayi]
    @Query private var turlar: [TurDurumu]
    @Query private var kullanim: [KullanimKaydi]
    @Query(sort: \IpucuOlayi.tarih) private var ipucuOlaylari: [IpucuOlayi]

    @State private var ayarlarAcik = false
    @State private var paylasim: PaylasimDosyasi?
    @State private var ayarSurumu = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    icerikGrubu
                    ogrenmeGrubu
                    soruGrubu
                    kullanimGrubu
                    Button {
                        paylasim = CSVDisaAktarim.olustur(context).map(PaylasimDosyasi.init)
                    } label: {
                        Label("CSV dışa aktar", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Tema.metin)
                }
                .padding(16)
                .id(ayarSurumu)
            }
            .background(Tema.arkaPlan)
            .navigationTitle("Ölçüm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarlarAcik = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $ayarlarAcik, onDismiss: { ayarSurumu += 1 }) {
                AyarlarView(dersler: icerikPaketleri.map(\.ders))
            }
            .sheet(item: $paylasim) { PaylasimSayfasi(url: $0.url) }
        }
    }

    // MARK: - Ortak

    /// Editör'ün "Yazdıklarım" paketi içerik sayılarına girmez.
    private var icerikPaketleri: [Paket] { paketler.filter { !$0.kullaniciMi } }

    private var soruSozlugu: [String: Soru] {
        Dictionary(sorular.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func kalip(_ s: Soru) -> KalipTipi? { s.kalipTipi }

    private func oran(_ d: Int, _ n: Int) -> String { n == 0 ? "—" : "%\(Int((Double(d) / Double(n) * 100).rounded()))" }

    // MARK: - 1. İçerik

    private var icerikGrubu: some View {
        let soruluKazanim = Set(sorular.compactMap { s in s.kazanim.map { "\(s.paket?.paket_id ?? "").\($0)" } })
        let sorusuz = kazanimlar.filter { !soruluKazanim.contains("\($0.paket?.paket_id ?? "").\($0.id)") }.count
        let levhaSayisi = paketler.reduce(0) { $0 + $1.levhalar.count }
        let yazdiklarim = sorular.filter(\.kullaniciSorusu).count
        return OlcumKarti(baslik: "İçerik", simge: "shippingbox") {
            HStack(spacing: 8) {
                SayiKutusu(deger: "\(icerikPaketleri.count)", ad: "paket")
                SayiKutusu(deger: "\(levhaSayisi)", ad: "levha")
                SayiKutusu(deger: "\(sorular.count)", ad: "soru")
                SayiKutusu(deger: "\(kazanimlar.count)", ad: "kazanım")
            }
            if yazdiklarim > 0 {
                Label("\(yazdiklarim) soru Editör'de yazıldı (Yazdıklarım)", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RenkSeti.mavi.yazi)
            }
            if sorusuz > 0 {
                Label("\(sorusuz) kazanımın sorusu yok", systemImage: "questionmark.square.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RenkSeti.sari.yazi)
            }
            ForEach(dersBolumler, id: \.ad) { satir in
                HStack {
                    Text(satir.ad).font(.system(size: 13.5))
                    Spacer()
                    Text("\(satir.levha) levha").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

    private var dersBolumler: [(ad: String, levha: Int)] {
        var sira: [String] = []
        var sayi: [String: Int] = [:]
        for p in icerikPaketleri {
            let ad = "\(p.ders) › \(p.bolum)"
            if sayi[ad] == nil { sira.append(ad) }
            sayi[ad, default: 0] += p.levhalar.count
        }
        return sira.map { ($0, sayi[$0] ?? 0) }
    }

    // MARK: - 2. Öğrenme

    private var ogrenmeGrubu: some View {
        let calisilan = durumlar.filter { $0.sonGorulme != nil || $0.sonrakiTarih != nil }
        let kovalar = ["0–20", "20–40", "40–60", "60–80", "80–100"]
        let histogram = kovalar.enumerated().map { i, ad in
            (ad: ad, n: calisilan.filter { min(4, Int($0.saglamlik / 20)) == i }.count)
        }
        let kutular = (0...4).map { k in (kutu: "Kutu \(k)", n: durumlar.filter { $0.sonrakiTarih != nil && $0.kutu == k }.count) }
        let (g7, g30) = gecikmeliHatirlama
        return OlcumKarti(baslik: "Öğrenme", simge: "brain.head.profile") {
            Text("Sağlamlık dağılımı · \(calisilan.count) çalışılmış levha")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            Chart(histogram, id: \.ad) { kova in
                BarMark(x: .value("Sağlamlık", kova.ad), y: .value("Levha", kova.n))
                    .foregroundStyle(RenkSeti.yesil.kenar)
                    .annotation(position: .top) { Text("\(kova.n)").font(.system(size: 10)).foregroundStyle(Tema.ikincil) }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)

            Text("Gecikmeli hatırlama (Örtme'de bildim oranı)")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                SayiKutusu(deger: oran(g7.bildim, g7.toplam), ad: "≥7 gün sonra · n=\(g7.toplam)")
                SayiKutusu(deger: oran(g30.bildim, g30.toplam), ad: "≥30 gün sonra · n=\(g30.toplam)")
            }

            Text("Kutu dağılımı").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            Chart(kutular, id: \.kutu) { k in
                BarMark(x: .value("Kutu", k.kutu), y: .value("Levha", k.n))
                    .foregroundStyle(RenkSeti.mavi.kenar)
                    .annotation(position: .top) { Text("\(k.n)").font(.system(size: 10)).foregroundStyle(Tema.ikincil) }
            }
            .chartYAxis(.hidden)
            .frame(height: 100)
        }
    }

    /// Bir levhanın Örtme oturumu, aynı levhanın önceki oturumundan ≥7 (≥30) gün sonra yapıldıysa sayılır.
    private var gecikmeliHatirlama: ((bildim: Int, toplam: Int), (bildim: Int, toplam: Int)) {
        var oturumlar: [String: [(tarih: Date, bildim: Int, toplam: Int)]] = [:]
        for o in ortmeler {
            var dizi = oturumlar[o.levhaId] ?? []
            if let son = dizi.last, son.tarih == o.tarih {
                dizi[dizi.count - 1] = (son.tarih, son.bildim + (o.bildim ? 1 : 0), son.toplam + 1)
            } else {
                dizi.append((o.tarih, o.bildim ? 1 : 0, 1))
            }
            oturumlar[o.levhaId] = dizi
        }
        var g7 = (bildim: 0, toplam: 0), g30 = (bildim: 0, toplam: 0)
        for dizi in oturumlar.values where dizi.count > 1 {
            for i in 1..<dizi.count {
                let gun = dizi[i].tarih.timeIntervalSince(dizi[i - 1].tarih) / 86_400
                if gun >= 7 { g7.bildim += dizi[i].bildim; g7.toplam += dizi[i].toplam }
                if gun >= 30 { g30.bildim += dizi[i].bildim; g30.toplam += dizi[i].toplam }
            }
        }
        return (g7, g30)
    }

    // MARK: - 3. Soru

    private var soruGrubu: some View {
        let sozluk = soruSozlugu
        return OlcumKarti(baslik: "Soru", simge: "questionmark.circle") {
            kalipTablosu(sozluk)
            Divider()
            kirmaSayaclari(sozluk)
            Divider()
            ipucuGecikmesi(sozluk)
            Divider()
            karistirmaMatrisi(sozluk)
            Divider()
            tahminiNet(sozluk)
            Divider()
            tahminVerimliligi(sozluk)
        }
    }

    private func kalipTablosu(_ sozluk: [String: Soru]) -> some View {
        var sayac: [KalipTipi: (d: Int, n: Int)] = [:]
        for o in soruOlaylari {
            guard let s = sozluk[o.soruGlobalId], let k = kalip(s) else { continue }
            let e = sayac[k] ?? (0, 0)
            sayac[k] = (e.d + (o.dogruMu ? 1 : 0), e.n + 1)
        }
        let enKotu = Set(sayac.filter { $0.value.n > 0 }
            .sorted { (Double($0.value.d) / Double($0.value.n), -$0.value.n) < (Double($1.value.d) / Double($1.value.n), -$1.value.n) }
            .prefix(3).map(\.key))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Kalıp doğruluğu").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            ForEach(KalipTipi.allCases, id: \.self) { k in
                let e = sayac[k] ?? (0, 0)
                let kotu = enKotu.contains(k)
                HStack {
                    Text(k.ad).font(.system(size: 13.5, weight: kotu ? .bold : .regular))
                    Spacer()
                    Text("\(e.n) soru").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Tema.ikincil)
                    Text(oran(e.d, e.n))
                        .font(.system(size: 13.5, weight: .bold).monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
                .foregroundStyle(kotu ? RenkSeti.kirmizi.yazi : Tema.metin)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(kotu ? RenkSeti.kirmizi.zemin : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Soru kırma: kalıp doğru + cevap yanlış = bilgi eksiği; kalıp yanlış (ya da süre doldu) + cevap yanlış = okuma eksiği;
    /// yanıltıcı ipucuna dokunmak = ringaya kandın (cevaptan bağımsız).
    private func kirmaSayaclari(_ sozluk: [String: Soru]) -> some View {
        var bilgi = 0, okuma = 0, ringa = 0, kirilan = 0
        var kalipDagilimi: [KalipTipi: (bilgi: Int, okuma: Int, ringa: Int)] = [:]
        for o in soruOlaylari where o.kirmaSuresi != nil {
            guard let s = sozluk[o.soruGlobalId] else { continue }
            kirilan += 1
            let gercek = s.kalipTipi
            var e = gercek.flatMap { kalipDagilimi[$0] } ?? (0, 0, 0)
            switch KirmaSinifi.sinifla(kalipTahmini: o.kalipTahmini, gercekKalip: gercek?.rawValue, cevapDogru: o.dogruMu) {
            case .bilgiEksigi: bilgi += 1; e.bilgi += 1
            case .okumaEksigi: okuma += 1; e.okuma += 1
            case nil: break
            }
            let ip = s.ipuclari
            if let i = o.ipucuTahminiIndeks, ip.indices.contains(i), ip[i].yanilticiMi { ringa += 1; e.ringa += 1 }
            if let gercek { kalipDagilimi[gercek] = e }
        }
        let satirlar = KalipTipi.allCases.compactMap { k in kalipDagilimi[k].flatMap { $0.bilgi + $0.okuma + $0.ringa > 0 ? (k, $0) : nil } }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Soru kırma · \(kirilan) soru").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                SayiKutusu(deger: "\(bilgi)", ad: "Bilgi eksiği")
                SayiKutusu(deger: "\(okuma)", ad: "Okuma eksiği")
                SayiKutusu(deger: "\(ringa)", ad: "Ringaya kandın")
            }
            if satirlar.isEmpty {
                Text(kirilan == 0 ? "Henüz kırma ile çözülmüş soru yok." : "Kırılan sorularda eksik yok.")
                    .font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            } else {
                HStack {
                    Text("Kalıp").frame(maxWidth: .infinity, alignment: .leading)
                    Text("bilgi").frame(width: 44)
                    Text("okuma").frame(width: 48)
                    Text("ringa").frame(width: 44)
                }
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(Tema.ikincil)
                ForEach(satirlar, id: \.0) { k, e in
                    HStack {
                        Text(k.ad).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(e.bilgi)").frame(width: 44)
                        Text("\(e.okuma)").frame(width: 48)
                        Text("\(e.ringa)").frame(width: 44)
                    }
                    .font(.system(size: 13).monospacedDigit())
                }
            }
        }
    }

    /// İpucu gecikmesi = ortalama(açılan ipucu / toplam ipucu), son 14 gün; düşük = erken tanı.
    private func ipucuGecikmesi(_ sozluk: [String: Soru]) -> some View {
        let sinir = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let son = ipucuOlaylari.filter { $0.tarih >= sinir }
        var kaliplar: [KalipTipi: [Double]] = [:]
        for o in son {
            guard let k = sozluk[o.soruGlobalId]?.kalipTipi else { continue }
            kaliplar[k, default: []].append(o.gecikme)
        }
        func ort(_ x: [Double]) -> String { x.isEmpty ? "—" : "%\(Int((x.reduce(0, +) / Double(x.count) * 100).rounded()))" }
        let puanOrt = son.isEmpty ? "—" : Bicim.sayi((Double(son.map(\.puan).reduce(0, +)) / Double(son.count)).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            Text("İpucu gecikmesi · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                SayiKutusu(deger: ort(son.map(\.gecikme)), ad: "ortalama gecikme (düşük = erken)")
                SayiKutusu(deger: puanOrt, ad: "ortalama puan · n=\(son.count)")
            }
            ForEach(KalipTipi.allCases.filter { kaliplar[$0] != nil }, id: \.self) { k in
                let x = kaliplar[k] ?? []
                HStack {
                    Text(k.ad).font(.system(size: 13.5))
                    Spacer()
                    Text("n=\(x.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Tema.ikincil)
                    Text(ort(x)).font(.system(size: 13.5, weight: .bold).monospacedDigit()).frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func karistirmaMatrisi(_ sozluk: [String: Soru]) -> some View {
        struct Cift: Hashable { let secilen: String; let dogru: String }
        var sayac: [Cift: Int] = [:]
        var ipucu: [Cift: String] = [:]
        for o in soruOlaylari where !o.dogruMu {
            guard let s = sozluk[o.soruGlobalId] else { continue }
            let aile = s.secenekAileleri
            guard let x = aile[o.secilen], let y = aile[s.dogru], x != y else { continue }
            let c = Cift(secilen: x, dogru: y)
            sayac[c, default: 0] += 1
            if ipucu[c] == nil {
                ipucu[c] = s.konuPaketi?.aileler.lazy.compactMap { $0.ayiriciIpucu(x, y) }.first
            }
        }
        let ilk10 = sayac.sorted { ($0.value, $1.key.secilen) > ($1.value, $0.key.secilen) }.prefix(10)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Karıştırma matrisi").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if ilk10.isEmpty {
                Text("Henüz aile eşlemeli yanlış yok.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
            ForEach(Array(ilk10), id: \.key) { c, n in
                VStack(alignment: .leading, spacing: 2) {
                    // Ek almayan kalıp: "X ile Y karışıyor" (Türkçe ek, ünlü uyumuna göre değişir).
                    Text("«\(c.dogru)» ile «\(c.secilen)» karışıyor · \(n) kez")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                    Text("Doğrusu «\(c.dogru)», sen «\(c.secilen)» dedin.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.ikincil)
                    if let i = ipucu[c] {
                        Text("Ayırıcı: \(i)").font(.system(size: 12.5)).foregroundStyle(RenkSeti.sari.yazi)
                    }
                }
            }
        }
    }

    private func tahminiNet(_ sozluk: [String: Soru]) -> some View {
        let sinir = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        var dersler: [String: [(sorulabilirlik: Int, dogru: Bool)]] = [:]
        for o in soruOlaylari where o.tarih >= sinir {
            guard let s = sozluk[o.soruGlobalId], let ders = s.konuPaketi?.ders else { continue }
            dersler[ders, default: []].append((s.sorulabilirlik ?? 3, o.dogruMu))
        }
        let ceza = SinavAyarlari.ceza
        let siralı = dersler.keys.sorted()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Tahmini net · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if siralı.isEmpty {
                Text("Son 14 günde soru çözülmedi.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
            ForEach(siralı, id: \.self) { ders in
                let N = SinavAyarlari.soruSayisi(ders)
                let t = NetHesabi.tahmin(cevaplar: dersler[ders] ?? [], N: N, ceza: ceza)
                HStack(alignment: .firstTextBaseline) {
                    Text(ders).font(.system(size: 14.5, weight: .bold))
                    Spacer()
                    if t.yetersiz {
                        Text("yetersiz veri (n=\(t.n))").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                    } else {
                        Text("\(Bicim.sayi(t.alt.rounded()))–\(Bicim.sayi(t.ust.rounded())) net")
                            .font(.system(size: 16, weight: .heavy).monospacedDigit())
                        Text("/\(N) · n=\(t.n)").font(.system(size: 12)).foregroundStyle(Tema.ikincil)
                    }
                }
            }
        }
    }

    private func tahminVerimliligi(_ sozluk: [String: Soru]) -> some View {
        let esik = NetHesabi.tahminEsigi(ceza: SinavAyarlari.ceza)
        let guvenli = soruOlaylari.filter { $0.guven != nil }
        func dogruluk(_ g: Int) -> (d: Int, n: Int) {
            let x = guvenli.filter { $0.guven == g }
            return (x.filter(\.dogruMu).count, x.count)
        }
        let tahmin = dogruluk(3)
        var kalipTahmin: [KalipTipi: (d: Int, n: Int)] = [:]
        for o in guvenli where o.guven == 3 {
            guard let s = sozluk[o.soruGlobalId], let k = kalip(s) else { continue }
            let e = kalipTahmin[k] ?? (0, 0)
            kalipTahmin[k] = (e.d + (o.dogruMu ? 1 : 0), e.n + 1)
        }
        func etiket(_ e: (d: Int, n: Int)) -> (String, RenkSeti) {
            guard e.n > 0 else { return ("veri yok", .gri) }
            return Double(e.d) / Double(e.n) > esik ? ("tahmin et", .yesil) : ("boş bırak", .kirmizi)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Tahmin verimliliği · eşik %\(Int((esik * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            let (e, r) = etiket(tahmin)
            HStack {
                Text("Tahmin dediklerin: \(oran(tahmin.d, tahmin.n)) doğru (n=\(tahmin.n))").font(.system(size: 13.5))
                Spacer()
                Rozet(metin: e, renk: r)
            }
            ForEach(KalipTipi.allCases.filter { kalipTahmin[$0] != nil }, id: \.self) { k in
                let v = kalipTahmin[k] ?? (0, 0)
                let (e, r) = etiket(v)
                HStack {
                    Text("· \(k.ad): \(oran(v.d, v.n)) (n=\(v.n))").font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                    Spacer()
                    Rozet(metin: e, renk: r)
                }
            }
            let emin = dogruluk(1), sanirim = dogruluk(2)
            Text("Kalibrasyon: Eminim dediklerinin \(oran(emin.d, emin.n))'i (n=\(emin.n)), Sanırım dediklerinin \(oran(sanirim.d, sanirim.n))'i (n=\(sanirim.n)) doğru.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.metin)
            let eski = soruOlaylari.count - guvenli.count
            if eski > 0 {
                Text("Güven kaydı olmayan \(eski) cevap hariç (İpucu avı ve eski kayıtlar).").font(.system(size: 11.5)).foregroundStyle(Tema.ikincil)
            }
        }
    }

    // MARK: - 4. Kullanım

    private var kullanimGrubu: some View {
        let takvim = Calendar.current
        let bugun = Zamanlayici.calismaGunu(.now, takvim: takvim)
        let sozluk = Dictionary(kullanim.map { ($0.gun, $0.saniye) }, uniquingKeysWith: +)
        // Çalışma gününün öğlesi: 04:00 kaydırması anahtarı bir önceki güne düşürmesin.
        func anahtar(_ g: Date) -> String { Zamanlayici.gunAnahtari(g.addingTimeInterval(12 * 3600), takvim: takvim) }
        let gunler: [(gun: Date, dk: Int)] = (0..<14).reversed().compactMap { geri in
            guard let g = takvim.date(byAdding: .day, value: -geri, to: bugun) else { return nil }
            return (g, Int(((sozluk[anahtar(g)] ?? 0) / 60).rounded()))
        }
        let anahtarlar = Set(gunler.map { anahtar($0.gun) })
        let sonTurlar = turlar.filter { anahtarlar.contains($0.gun) }
        let tamamlanan = sonTurlar.reduce(0) { $0 + TurPlanlayici.tamamlananDakika($1) }
        let planlanan = sonTurlar.reduce(0) { $0 + TurPlanlayici.planlananDakika($1) }
        let yerler = CalismaYeri.allCases.map { y in (ad: y.ad, n: sonTurlar.filter { $0.calismaYeri == y.rawValue }.count) }
        return OlcumKarti(baslik: "Kullanım", simge: "clock") {
            Text("Günlük dakika · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            // Gün etiketleri kategorik: çalışma günü (04:00 dönüşü) ile takvim günü arasında kayma olmaz.
            let etiketler = gunler.map { Bicim.tarih($0.gun) }
            let gosterilen = Set(etiketler.enumerated().filter { ($0.offset - (etiketler.count - 1)) % 3 == 0 }.map(\.element))
            Chart(Array(zip(etiketler, gunler.map(\.dk))), id: \.0) { gun, dk in
                BarMark(x: .value("Gün", gun), y: .value("Dakika", dk))
                    .foregroundStyle(Tema.metin)
            }
            .chartXAxis {
                AxisMarks(values: etiketler) { deger in
                    if let e = deger.as(String.self), gosterilen.contains(e) { AxisValueLabel(e, anchor: .topTrailing) }
                }
            }
            .frame(height: 120)
            HStack(spacing: 8) {
                SayiKutusu(deger: oran(tamamlanan, planlanan), ad: "tur tamamlama (\(tamamlanan)/\(planlanan) dk)")
                SayiKutusu(deger: "\(gunler.reduce(0) { $0 + $1.dk })", ad: "toplam dakika")
            }
            Text("Çalışma yeri (gün)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                ForEach(yerler, id: \.ad) { SayiKutusu(deger: "\($0.n)", ad: $0.ad) }
            }
        }
    }
}

// MARK: - Parçalar

struct OlcumKarti<Icerik: View>: View {
    let baslik: String
    let simge: String
    @ViewBuilder var icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(baslik, systemImage: simge)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tema.metin)
            icerik
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .levhaKarti()
    }
}

struct SayiKutusu: View {
    let deger: String
    let ad: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deger)
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(Tema.metin)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(ad)
                .font(.system(size: 11.5))
                .foregroundStyle(Tema.ikincil)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.arkaPlan, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Rozet: View {
    let metin: String
    let renk: RenkSeti

    var body: some View {
        Text(metin)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(renk.yazi)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(renk.zemin, in: Capsule())
            .overlay(Capsule().strokeBorder(renk.kenar, lineWidth: 1))
    }
}

struct PaylasimDosyasi: Identifiable {
    let url: URL
    var id: URL { url }
}

struct PaylasimSayfasi: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - CSV

enum CSVDisaAktarim {
    /// Tüm olay tablolarını CSV yazar, tek zip'te toplar (NSFileCoordinator .forUploading ile).
    @MainActor
    static func olustur(_ context: ModelContext) -> URL? {
        let fm = FileManager.default
        let gun = DurumServisi.gunAnahtari()
        let klasor = fm.temporaryDirectory.appending(path: "levha-olaylar-\(gun)", directoryHint: .isDirectory)
        try? fm.removeItem(at: klasor)
        try? fm.createDirectory(at: klasor, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        func t(_ d: Date?) -> String { d.map { iso.string(from: $0) } ?? "" }
        func yaz<T: PersistentModel>(_ ad: String, _ tip: T.Type, _ baslik: [String], _ satir: (T) -> [String]) {
            let kayitlar = (try? context.fetch(FetchDescriptor<T>())) ?? []
            let metin = ([baslik] + kayitlar.map(satir))
                .map { $0.map(kacir).joined(separator: ",") }
                .joined(separator: "\n")
            try? metin.write(to: klasor.appending(path: "\(ad).csv"), atomically: true, encoding: .utf8)
        }
        yaz("ortme", OrtmeOlayi.self, ["levhaId", "dugumId", "tarih", "bildim"]) { [$0.levhaId, $0.dugumId, t($0.tarih), "\($0.bildim)"] }
        yaz("soru", SoruOlayi.self, ["soruGlobalId", "levhaId", "secilen", "dogruMu", "guven", "sureSaniye", "tarih",
                                     "kalipTahmini", "ipucuTahminiIndeks", "kirmaSuresi"]) {
            [$0.soruGlobalId, $0.levhaId, "\($0.secilen)", "\($0.dogruMu)", $0.guven.map(String.init) ?? "", String(format: "%.1f", $0.sureSaniye), t($0.tarih),
             $0.kalipTahmini ?? "", $0.ipucuTahminiIndeks.map(String.init) ?? "", $0.kirmaSuresi.map { String(format: "%.1f", $0) } ?? ""]
        }
        yaz("ipucu", IpucuOlayi.self, ["soruGlobalId", "ipucuIndeks", "toplamIpucu", "dogru", "puan", "tarih"]) {
            [$0.soruGlobalId, "\($0.ipucuIndeks)", "\($0.toplamIpucu)", "\($0.dogru)", "\($0.puan)", t($0.tarih)]
        }
        yaz("editor", EditorOlayi.self, ["levhaId", "puan", "kaydedildi", "tarih"]) {
            [$0.levhaId, $0.puan.map(String.init) ?? "", "\($0.kaydedildi)", t($0.tarih)]
        }
        yaz("sabotaj", SabotajOlayi.self, ["levhaId", "sabotajTipi", "bulundu", "denemeSayisi", "tarih"]) {
            [$0.levhaId, $0.sabotajTipi, "\($0.bulundu)", "\($0.denemeSayisi)", t($0.tarih)]
        }
        yaz("insa", InsaOlayi.self, ["levhaId", "hataSayisi", "toplam", "sureSaniye", "tarih"]) {
            [$0.levhaId, "\($0.hataSayisi)", "\($0.toplam)", String(format: "%.1f", $0.sureSaniye), t($0.tarih)]
        }
        yaz("levha_durumu", LevhaDurumu.self, ["levhaId", "kutu", "saglamlik", "sonrakiTarih", "sonGorulme"]) {
            [$0.levhaId, "\($0.kutu)", String(format: "%.1f", $0.saglamlik), t($0.sonrakiTarih), t($0.sonGorulme)]
        }
        yaz("dugum_zayiflik", DugumZayiflik.self, ["levhaId", "dugumId", "sayac"]) { [$0.levhaId, $0.dugumId, "\($0.sayac)"] }
        yaz("tur", TurDurumu.self, ["gun", "calismaYeri", "altKonuPaketId", "kisa", "tamamlananlar"]) {
            [$0.gun, $0.calismaYeri, $0.altKonuPaketId ?? "", "\($0.kisa)", $0.tamamlananlar.joined(separator: " ")]
        }
        yaz("kullanim", KullanimKaydi.self, ["gun", "saniye"]) { [$0.gun, String(format: "%.0f", $0.saniye)] }

        var zip: URL?
        var hata: NSError?
        NSFileCoordinator().coordinate(readingItemAt: klasor, options: .forUploading, error: &hata) { gecici in
            let hedef = fm.temporaryDirectory.appending(path: "levha-olaylar-\(gun).zip")
            try? fm.removeItem(at: hedef)
            if (try? fm.copyItem(at: gecici, to: hedef)) != nil { zip = hedef }
        }
        return zip
    }

    private static func kacir(_ alan: String) -> String {
        guard alan.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return alan }
        return "\"\(alan.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
