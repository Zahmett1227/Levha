import SwiftUI
import SwiftData
import Charts

/// Ölçüm: İçerik · Öğrenme · Soru · Kullanım. Olaylar arka planda tek geçişte toplanır (`OlcumOzeti`);
/// özet yalnız yeni olay yazılınca (`OlayDefteri.surum`) yeniden hesaplanır.
struct OlcumSekmesi: View {
    @Environment(\.modelContext) private var context
    @State private var ayarlarAcik = false
    @State private var acilis: Date?
    private var onbellek = OlcumOnbellegi.ortak
    private var ozet: OlcumOzeti? { onbellek.ozet }
    @State private var paylasim: PaylasimDosyasi?
    private var yonlendirici = Yonlendirici.ortak

    var body: some View {
        NavigationStack {
            ScrollView {
                if let o = ozet {
                    VStack(alignment: .leading, spacing: 14) {
                        icerikGrubu(o)
                        ogrenmeGrubu(o)
                        soruGrubu(o)
                        kullanimGrubu(o)
                        Button {
                            paylasim = CSVDisaAktarim.olustur(context).map(PaylasimDosyasi.init)
                        } label: {
                            Label("CSV dışa aktar", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(Tema.metin)
                        Text("\(Bicim.sayi(Double(o.olaySayisi))) olay · özet \(Int(o.sureMs.rounded())) ms (arka planda)"
                             + (onbellek.guncel ? "" : " · güncelleniyor"))
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.cizgi)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .onAppear { acilisBitti(onbellekten: true) }
                } else {
                    ProgressView("Hesaplanıyor…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .background(Tema.arkaPlan)
            .navigationTitle("Ölçüm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarlarAcik = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $ayarlarAcik, onDismiss: { OlayDefteri.degisti() }) {
                AyarlarView(dersler: ozet?.dersler ?? [])
            }
            .sheet(item: $paylasim) { PaylasimSayfasi(url: $0.url) }
        }
        // Özet eskiyse arka planda yenilenir; o sırada önceki özet görünür.
        .onChange(of: yonlendirici.sekme, initial: true) { _, yeni in
            guard yeni == .olcum else { return }
            acilis = .now
            onbellek.isit(context.container, gecikme: .zero)
        }
        .onChange(of: onbellek.ozet != nil) { if onbellek.ozet != nil { acilisBitti(onbellekten: false) } }
    }

    /// Sekme seçiminden içeriğin görünmesine kadar geçen süre (Ölçüm hedefi < 300 ms).
    private func acilisBitti(onbellekten: Bool) {
        guard let bas = acilis else { return }
        acilis = nil
        let ms = Date.now.timeIntervalSince(bas) * 1000
        OlcumHesaplayici.gunluk.notice("Ölçüm açılış: \(String(format: "%.0f", ms)) ms (\(onbellekten ? "önbellekten" : "yeni hesap"))")
    }

    // MARK: - Ortak

    private func oran(_ d: Int, _ n: Int) -> String { n == 0 ? "—" : "%\(Int((Double(d) / Double(n) * 100).rounded()))" }
    private func oran(_ s: Sayac) -> String { oran(s.d, s.n) }

    // MARK: - 1. İçerik

    private func icerikGrubu(_ o: OlcumOzeti) -> some View {
        OlcumKarti(baslik: "İçerik", simge: "shippingbox") {
            HStack(spacing: 8) {
                SayiKutusu(deger: "\(o.paketSayisi)", ad: "paket")
                SayiKutusu(deger: "\(o.levhaSayisi)", ad: "levha")
                SayiKutusu(deger: "\(o.soruSayisi)", ad: "soru")
                SayiKutusu(deger: "\(o.kazanimSayisi)", ad: "kazanım")
            }
            if o.soruPaketiSayisi > 0 {
                Label("\(o.soruPaketiSayisi) soru paketi · \(o.bagimsizSoru) bağımsız soru", systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RenkSeti.mavi.yazi)
            }
            if o.yazdiklarim > 0 {
                Label("\(o.yazdiklarim) soru Editör'de yazıldı (Yazdıklarım)", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RenkSeti.mavi.yazi)
            }
            if o.sorusuzKazanim > 0 {
                Label("\(o.sorusuzKazanim) kazanımın sorusu yok", systemImage: "questionmark.square.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RenkSeti.sari.yazi)
            }
            if o.paketSayisi == 0 {
                Text("Henüz paket yok. İçerik sekmesinden içe aktar.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
            ForEach(o.dersBolumler, id: \.ad) { satir in
                HStack {
                    Text(satir.ad).font(.system(size: 13.5))
                    Spacer()
                    Text("\(satir.levha) levha").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

    // MARK: - 2. Öğrenme

    private func ogrenmeGrubu(_ o: OlcumOzeti) -> some View {
        let kovalar = ["0–20", "20–40", "40–60", "60–80", "80–100"]
        let histogram = kovalar.enumerated().map { (ad: $0.element, n: o.histogram[$0.offset]) }
        let kutular = (0...4).map { (kutu: "Kutu \($0)", n: o.kutular[$0]) }
        return OlcumKarti(baslik: "Öğrenme", simge: "brain.head.profile") {
            Text("Sağlamlık dağılımı · \(o.calisilan) çalışılmış levha")
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
                SayiKutusu(deger: oran(o.g7), ad: "≥7 gün sonra · n=\(o.g7.n)")
                SayiKutusu(deger: oran(o.g30), ad: "≥30 gün sonra · n=\(o.g30.n)")
            }

            Text("Kutu dağılımı").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            Chart(kutular, id: \.kutu) { k in
                BarMark(x: .value("Kutu", k.kutu), y: .value("Levha", k.n))
                    .foregroundStyle(RenkSeti.mavi.kenar)
                    .annotation(position: .top) { Text("\(k.n)").font(.system(size: 10)).foregroundStyle(Tema.ikincil) }
            }
            .chartYAxis(.hidden)
            .frame(height: 100)

            Divider()
            abKarti(o.ab)
        }
    }

    @ViewBuilder
    private func abKarti(_ ab: ABOzeti?) -> some View {
        Text("A/B deneyi · levha mı, metin mi?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
        if let ab {
            Text("\(Bicim.tarih(ab.baslangic))'den beri · \(ab.levhaPaket) alt konu levha, \(ab.metinPaket) alt konu metin")
                .font(.system(size: 12)).foregroundStyle(Tema.ikincil)
            ABSatiri(ad: "Soru doğruluğu (7+ gün)", levha: ab.soru.levha, metin: ab.soru.metin)
            ABSatiri(ad: "Örtme / cloze bildim (7+ gün)", levha: ab.ortme.levha, metin: ab.ortme.metin)
        } else {
            Text("Deney kapalı. Ayarlar › A/B deneyi › Başlat.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
        }
    }

    // MARK: - 3. Soru

    private func soruGrubu(_ o: OlcumOzeti) -> some View {
        OlcumKarti(baslik: "Soru", simge: "questionmark.circle") {
            kalipTablosu(o)
            Divider()
            kirmaSayaclari(o)
            Divider()
            ipucuGecikmesi(o)
            Divider()
            karistirmaMatrisi(o)
            if !o.konuZayifliklari.isEmpty {
                Divider()
                bagimsizZayiflik(o)
            }
            Divider()
            tahminiNet(o)
            Divider()
            sinavKalibrasyonu(o)
            Divider()
            tahminVerimliligi(o)
        }
    }

    /// Bağımsız sorular (levhasız): yanlışlar kazanım ya da alt konu düzeyinde sayılır.
    private func bagimsizZayiflik(_ o: OlcumOzeti) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bağımsız sorularda zayıf noktalar").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            ForEach(Array(o.konuZayifliklari.enumerated()), id: \.offset) { _, z in
                HStack(alignment: .firstTextBaseline) {
                    Text(z.ad).font(.system(size: 13.5)).lineLimit(2)
                    Spacer()
                    Text("\(z.yanlis) yanlış · \(z.dogru) doğru")
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(RenkSeti.kirmizi.yazi)
                }
            }
        }
    }

    private func kalipTablosu(_ o: OlcumOzeti) -> some View {
        let enKotu = Set(o.kalip.filter { $0.value.n > 0 }
            .sorted { (Double($0.value.d) / Double($0.value.n), -$0.value.n) < (Double($1.value.d) / Double($1.value.n), -$1.value.n) }
            .prefix(3).map(\.key))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Kalıp doğruluğu").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            ForEach(KalipTipi.allCases, id: \.self) { k in
                let e = o.kalip[k] ?? Sayac()
                let kotu = enKotu.contains(k)
                HStack {
                    Text(k.ad).font(.system(size: 13.5, weight: kotu ? .bold : .regular))
                    Spacer()
                    Text("\(e.n) soru").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Tema.ikincil)
                    Text(oran(e))
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
    private func kirmaSayaclari(_ o: OlcumOzeti) -> some View {
        let satirlar = KalipTipi.allCases.compactMap { k in o.kirmaKalip[k].flatMap { $0.bilgi + $0.okuma + $0.ringa > 0 ? (k, $0) : nil } }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Soru kırma · \(o.kirma.kirilan) soru").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                SayiKutusu(deger: "\(o.kirma.bilgi)", ad: "Bilgi eksiği")
                SayiKutusu(deger: "\(o.kirma.okuma)", ad: "Okuma eksiği")
                SayiKutusu(deger: "\(o.kirma.ringa)", ad: "Ringaya kandın")
            }
            if satirlar.isEmpty {
                Text(o.kirma.kirilan == 0 ? "Henüz kırma ile çözülmüş soru yok." : "Kırılan sorularda eksik yok.")
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
    private func ipucuGecikmesi(_ o: OlcumOzeti) -> some View {
        func ort(_ x: [Double]) -> String { x.isEmpty ? "—" : "%\(Int((x.reduce(0, +) / Double(x.count) * 100).rounded()))" }
        let puanOrt = o.ipucuPuan.isEmpty ? "—" : Bicim.sayi((Double(o.ipucuPuan.reduce(0, +)) / Double(o.ipucuPuan.count)).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            Text("İpucu gecikmesi · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                SayiKutusu(deger: ort(o.ipucuGecikme), ad: "ortalama gecikme (düşük = erken)")
                SayiKutusu(deger: puanOrt, ad: "ortalama puan · n=\(o.ipucuPuan.count)")
            }
            ForEach(KalipTipi.allCases.filter { o.ipucuKalip[$0] != nil }, id: \.self) { k in
                let x = o.ipucuKalip[k] ?? []
                HStack {
                    Text(k.ad).font(.system(size: 13.5))
                    Spacer()
                    Text("n=\(x.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Tema.ikincil)
                    Text(ort(x)).font(.system(size: 13.5, weight: .bold).monospacedDigit()).frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func karistirmaMatrisi(_ o: OlcumOzeti) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Karıştırma matrisi").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if o.karistirma.isEmpty {
                Text("Henüz aile eşlemeli yanlış yok.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
            ForEach(o.karistirma, id: \.self) { c in
                VStack(alignment: .leading, spacing: 2) {
                    // Ek almayan kalıp: "X ile Y karışıyor" (Türkçe ek, ünlü uyumuna göre değişir).
                    Text("«\(c.dogru)» ile «\(c.secilen)» karışıyor · \(c.sayi) kez")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                    Text("Doğrusu «\(c.dogru)», sen «\(c.secilen)» dedin.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.ikincil)
                    if let i = c.ipucu {
                        Text("Ayırıcı: \(i)").font(.system(size: 12.5)).foregroundStyle(RenkSeti.sari.yazi)
                    }
                }
            }
        }
    }

    private func tahminiNet(_ o: OlcumOzeti) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tahmini net · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if o.netler.isEmpty {
                Text("Son 14 günde soru çözülmedi.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
            ForEach(o.netler, id: \.ders) { satir in
                let t = satir.tahmin
                HStack(alignment: .firstTextBaseline) {
                    Text(satir.ders).font(.system(size: 14.5, weight: .bold))
                    Spacer()
                    if t.yetersiz {
                        Text("yetersiz veri (n=\(t.n))").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                    } else {
                        Text("\(Bicim.sayi(t.alt.rounded()))–\(Bicim.sayi(t.ust.rounded())) net")
                            .font(.system(size: 16, weight: .heavy).monospacedDigit())
                        Text("/\(satir.N) · n=\(t.n)").font(.system(size: 12)).foregroundStyle(Tema.ikincil)
                    }
                }
            }
        }
    }

    /// Tahmini net vs gerçek net: son Mini sınavın neti ile sınav günü hesaplanan tahmin yan yana.
    private func sinavKalibrasyonu(_ o: OlcumOzeti) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tahmini net vs gerçek net").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if let s = o.sonSinav {
                HStack(spacing: 8) {
                    SayiKutusu(deger: Bicim.sayi(s.net), ad: "gerçek net · \(s.soruSayisi) soru · \(Bicim.tarih(s.tarih))")
                    SayiKutusu(deger: s.tahminAlt.flatMap { a in s.tahminUst.map { "\(Bicim.sayi(a.rounded()))–\(Bicim.sayi($0.rounded()))" } } ?? "—",
                               ad: s.tahminAlt == nil ? "sınav günü tahmin yoktu (az veri)" : "sınav günkü tahmin")
                }
                if let a = s.tahminAlt, let u = s.tahminUst {
                    let icinde = s.net >= a.rounded() && s.net <= u.rounded()
                    Text(icinde ? "Gerçek net tahmin aralığında: tahmin kalibre." :
                            (s.net > u ? "Gerçek net tahminin üstünde: tahmin seni küçümsüyor." : "Gerçek net tahminin altında: tahmin iyimser."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(icinde ? RenkSeti.yesil.yazi : RenkSeti.sari.yazi)
                }
            } else {
                Text("Henüz Mini sınav yok. Soru › Mini sınav.").font(.system(size: 13)).foregroundStyle(Tema.ikincil)
            }
        }
    }

    private func tahminVerimliligi(_ o: OlcumOzeti) -> some View {
        let esik = NetHesabi.tahminEsigi(ceza: SinavAyarlari.ceza)
        let tahmin = o.guven[3] ?? Sayac()
        func etiket(_ e: Sayac) -> (String, RenkSeti) {
            guard e.n > 0 else { return ("veri yok", .gri) }
            return Double(e.d) / Double(e.n) > esik ? ("tahmin et", .yesil) : ("boş bırak", .kirmizi)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Tahmin verimliliği · eşik %\(Int((esik * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            let (e, r) = etiket(tahmin)
            HStack {
                Text("Tahmin dediklerin: \(oran(tahmin)) doğru (n=\(tahmin.n))").font(.system(size: 13.5))
                Spacer()
                Rozet(metin: e, renk: r)
            }
            ForEach(KalipTipi.allCases.filter { o.kalipTahmin[$0] != nil }, id: \.self) { k in
                let v = o.kalipTahmin[k] ?? Sayac()
                let (e, r) = etiket(v)
                HStack {
                    Text("· \(k.ad): \(oran(v)) (n=\(v.n))").font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                    Spacer()
                    Rozet(metin: e, renk: r)
                }
            }
            let emin = o.guven[1] ?? Sayac(), sanirim = o.guven[2] ?? Sayac()
            Text("Kalibrasyon: Eminim dediklerinin \(oran(emin))'i (n=\(emin.n)), Sanırım dediklerinin \(oran(sanirim))'i (n=\(sanirim.n)) doğru.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.metin)
            if o.guvensiz > 0 {
                Text("Güven kaydı olmayan \(o.guvensiz) cevap hariç (İpucu avı, güven seçilmemiş sınav cevapları, eski kayıtlar).")
                    .font(.system(size: 11.5)).foregroundStyle(Tema.ikincil)
            }
        }
    }

    // MARK: - 4. Kullanım

    private func kullanimGrubu(_ o: OlcumOzeti) -> some View {
        OlcumKarti(baslik: "Kullanım", simge: "clock") {
            Text("Günlük dakika · son 14 gün").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            // Gün etiketleri kategorik: çalışma günü (04:00 dönüşü) ile takvim günü arasında kayma olmaz.
            let etiketler = o.gunler.map { Bicim.tarih($0.gun) }
            let gosterilen = Set(etiketler.enumerated().filter { ($0.offset - (etiketler.count - 1)) % 3 == 0 }.map(\.element))
            Chart(Array(zip(etiketler, o.gunler.map(\.dk))), id: \.0) { gun, dk in
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
                SayiKutusu(deger: oran(o.turTamamlanan, o.turPlanlanan), ad: "tur tamamlama (\(o.turTamamlanan)/\(o.turPlanlanan) dk)")
                SayiKutusu(deger: "\(o.gunler.reduce(0) { $0 + $1.dk })", ad: "toplam dakika")
            }
            Text("Çalışma yeri (gün)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                ForEach(o.yerler, id: \.ad) { SayiKutusu(deger: "\($0.n)", ad: $0.ad) }
            }
            Text("Model kullanımı").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            Text("Bu ay: \(o.llm.cagri) çağrı, \(Bicim.sayi(Double(o.llm.giris))) giriş / \(Bicim.sayi(Double(o.llm.cikis))) çıkış token")
                .font(.system(size: 13.5))
                .foregroundStyle(Tema.metin)
        }
    }
}

/// A/B kartında bir ölçüt: iki grubun oranı, fark ve z-testi p değeri.
struct ABSatiri: View {
    let ad: String
    let levha: Sayac
    let metin: Sayac

    var body: some View {
        let k = ABTesti.ikiOran(d1: levha.d, n1: levha.n, d2: metin.d, n2: metin.n)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ad).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                if k == nil || k?.yetersiz == true { Rozet(metin: "n < \(ABTesti.enAzOrneklem) · yetersiz", renk: .gri) }
            }
            HStack(spacing: 8) {
                SayiKutusu(deger: oranMetni(levha), ad: "levha · n=\(levha.n)")
                SayiKutusu(deger: oranMetni(metin), ad: "metin · n=\(metin.n)")
                SayiKutusu(deger: k.map { "\($0.fark >= 0 ? "+" : "−")\(Int((abs($0.fark) * 100).rounded()))" } ?? "—",
                           ad: k.map { "puan fark · p=\(Bicim.sayi(($0.pDegeri * 1000).rounded() / 1000))" } ?? "fark")
            }
        }
        .foregroundStyle(Tema.metin)
    }

    private func oranMetni(_ s: Sayac) -> String { s.n == 0 ? "—" : "%\(Int((Double(s.d) / Double(s.n) * 100).rounded()))" }
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
        yaz("ortme", OrtmeOlayi.self, ["levhaId", "dugumId", "tarih", "bildim", "abGrup"]) { [$0.levhaId, $0.dugumId, t($0.tarih), "\($0.bildim)", $0.abGrup ?? ""] }
        yaz("soru", SoruOlayi.self, ["soruGlobalId", "levhaId", "secilen", "dogruMu", "guven", "sureSaniye", "tarih",
                                     "kalipTahmini", "ipucuTahminiIndeks", "kirmaSuresi", "baglam", "abGrup"]) {
            [$0.soruGlobalId, $0.levhaId, "\($0.secilen)", "\($0.dogruMu)", $0.guven.map(String.init) ?? "", String(format: "%.1f", $0.sureSaniye), t($0.tarih),
             $0.kalipTahmini ?? "", $0.ipucuTahminiIndeks.map(String.init) ?? "", $0.kirmaSuresi.map { String(format: "%.1f", $0) } ?? "",
             $0.baglam ?? "", $0.abGrup ?? ""]
        }
        yaz("ipucu", IpucuOlayi.self, ["soruGlobalId", "ipucuIndeks", "toplamIpucu", "dogru", "puan", "tarih"]) {
            [$0.soruGlobalId, "\($0.ipucuIndeks)", "\($0.toplamIpucu)", "\($0.dogru)", "\($0.puan)", t($0.tarih)]
        }
        yaz("sinav", SinavOlayi.self, ["tarih", "soruSayisi", "net", "dogru", "yanlis", "bos", "sureSaniye", "tahminAlt", "tahminUst"]) {
            [t($0.tarih), "\($0.soruSayisi)", String(format: "%.2f", $0.net), "\($0.dogru)", "\($0.yanlis)", "\($0.bos)",
             String(format: "%.0f", $0.sureSaniye), $0.tahminAlt.map { String(format: "%.2f", $0) } ?? "", $0.tahminUst.map { String(format: "%.2f", $0) } ?? ""]
        }
        yaz("model_kullanimi", LLMKullanim.self, ["tarih", "amac", "giris", "cikis"]) { [t($0.tarih), $0.amac, "\($0.giris)", "\($0.cikis)"] }
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
        yaz("konu_zayiflik", KonuZayiflik.self, ["anahtar", "ders", "altKonu", "kazanimId", "yanlis", "dogru", "sonTarih"]) {
            [$0.anahtar, $0.ders, $0.altKonu, $0.kazanimId ?? "", "\($0.yanlis)", "\($0.dogru)", t($0.sonTarih)]
        }
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
