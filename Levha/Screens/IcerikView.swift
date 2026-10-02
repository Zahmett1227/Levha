import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct IcerikView: View {
    @ObservedObject var klasor: PaketKlasoru
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @Query(sort: \Taslak.tarih, order: .reverse) private var taslaklar: [Taslak]
    @State private var dosyaSeciliyor = false
    @State private var sonuclar: [PaketIceAktarici.Sonuc] = []
    @State private var taslakHatalari: [PersistentIdentifier: [String]] = [:]
    @State private var paylasim: PaylasimDosyasi?
    @State private var yedekSeciliyor = false
    @State private var bekleyenYedek: YedekPaketi?
    @State private var yedekMesaji: (metin: String, hata: Bool)?
    @Query private var bekleyenler: [BekleyenYedek]

    var body: some View {
        NavigationStack {
            List {
                if let hata = Depo.hata {
                    Section {
                        Label(hata, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RenkSeti.kirmizi.yazi)
                            .listRowBackground(RenkSeti.kirmizi.zemin)
                    }
                }
                Section {
                    LabeledContent("Klasör", value: klasor.konumAdi)
                        .font(.system(size: 14))
                    Button {
                        hepsiniIceAktar()
                    } label: {
                        Label("Hepsini içe aktar", systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(gecerliDosyalar.isEmpty)
                    Button {
                        dosyaSeciliyor = true
                    } label: {
                        Label("Dosya seç…", systemImage: "doc.badge.plus")
                    }
                } footer: {
                    Text(klasor.iCloud
                         ? "Files › iCloud Drive › Levha › Paketler klasörüne .json paket koy."
                         : "iCloud kapalı. Files › Bu iPhone'da › Levha › Paketler klasörüne .json paket koy.")
                }

                if !sonuclar.isEmpty {
                    Section("Son içe aktarma") {
                        ForEach(Array(sonuclar.enumerated()), id: \.offset) { _, s in
                            SonucSatiri(sonuc: s)
                        }
                    }
                }

                yedekBolumu

                if !taslaklar.isEmpty {
                    Section {
                        ForEach(taslaklar) { t in
                            TaslakSatiri(taslak: t, levha: levha(t.levhaId), hatalar: taslakHatalari[t.persistentModelID]) {
                                taslakHatalari[t.persistentModelID] = TaslakServisi.uygula(t, context)
                            }
                        }
                        .onDelete { indeksler in
                            for i in indeksler { context.delete(taslaklar[i]) }
                            try? context.save()
                        }
                    } header: {
                        Text("Taslaklar")
                    } footer: {
                        Text("\"Bu levhayı genişlet\" yanıtları. Eklenen düğümler yerel düzendir: paketin revizyonu artarsa paket kazanır.")
                    }
                }

                Section("Klasördeki dosyalar") {
                    if klasor.dosyalar.isEmpty {
                        Text("Klasörde .json dosyası yok.")
                            .foregroundStyle(Tema.ikincil)
                    }
                    ForEach(klasor.dosyalar) { d in
                        DosyaSatiri(dosya: d, iceAktarildi: iceAktarildiMi(d))
                    }
                }

                Section {
                    ForEach(paketler) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(p.ders) › \(p.bolum) › \(p.alt_konu)")
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(p.levhalar.count) levha · \(p.sorular.count) soru · \(p.paket_id)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Tema.ikincil)
                        }
                    }
                    .onDelete { indeksler in
                        for i in indeksler { context.delete(paketler[i]) }
                        try? context.save()
                    }
                } header: {
                    Text("İçe aktarılmış paketler")
                } footer: {
                    Text("Aynı id'li levha yeniden içe aktarılınca düzen ve taslaktan eklenen düğümler korunur; paketteki revizyon daha büyükse paketin düzeni kazanır. Notların (Notum) hiçbir durumda silinmez.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.arkaPlan)
            .navigationTitle("İçerik")
            .refreshable { klasor.tara() }
            .onAppear { klasor.tara() }
            .fileImporter(isPresented: $dosyaSeciliyor, allowedContentTypes: [.json], allowsMultipleSelection: true) { sonuc in
                if case .success(let urller) = sonuc { seciliDosyalariAktar(urller) }
            }
            .sheet(item: $paylasim) { PaylasimSayfasi(url: $0.url) }
            .background {
                // İkinci dosya seçici ayrı bir görünüme bağlanır (aynı görünümde iki fileImporter çakışır).
                Color.clear.fileImporter(isPresented: $yedekSeciliyor, allowedContentTypes: [.levhaYedek, .zip, .data]) { sonuc in
                    if case .success(let url) = sonuc { yedekOku(url) }
                }
            }
            .confirmationDialog("Yedeği geri yükle", isPresented: Binding(get: { bekleyenYedek != nil }, set: { if !$0 { bekleyenYedek = nil } }),
                                titleVisibility: .visible, presenting: bekleyenYedek) { y in
                Button("Birleştir (aynı kayıtlar atlanır)") { geriYukle(y, .birlestir) }
                Button("Üzerine yaz", role: .destructive) { geriYukle(y, .uzerineYaz) }
                Button("Vazgeç", role: .cancel) {}
            } message: { y in
                Text("\(Bicim.tarih(y.olusturma)) tarihli yedek: \(YedekServisi.ozet(y).metin).")
            }
        }
    }

    private var yedekBolumu: some View {
        Section {
            Button {
                do { paylasim = PaylasimDosyasi(url: try YedekServisi.dosya(context)) }
                catch { yedekMesaji = ("Yedek oluşturulamadı: \(error.localizedDescription)", true) }
            } label: {
                Label("Yedekle", systemImage: "externaldrive.badge.checkmark")
            }
            Button {
                yedekSeciliyor = true
            } label: {
                Label("Geri yükle…", systemImage: "clock.arrow.circlepath")
            }
            if let m = yedekMesaji {
                Label(m.metin, systemImage: m.hata ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.hata ? RenkSeti.kirmizi.yazi : RenkSeti.yesil.yazi)
            }
            if !bekleyenler.isEmpty {
                Label("\(bekleyenler.count) yerel düğüm eki, levhası içe aktarılınca bağlanacak", systemImage: "hourglass")
                    .font(.system(size: 13))
                    .foregroundStyle(RenkSeti.sari.yazi)
            }
        } header: {
            Text("Yedek")
        } footer: {
            Text("Olaylar, notlar, sohbetler, taslaklar, Yazdıklarım, yerel düğümler, A/B grupları ve ayarlar (API anahtarı hariç); paket içeriği girmez. Her gün 04:00 dönüşünden sonraki ilk açılışta \(YedekServisi.yedekKlasoruAdi(klasor)) klasörüne otomatik yedek alınır; son 7 gün tutulur.")
        }
    }

    private func yedekOku(_ url: URL) {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let veri = PaketKlasoru.oku(url) else { throw ZipArsiv.Hata.bozuk("dosya okunamadı") }
            bekleyenYedek = try YedekServisi.coz(veri)
        } catch {
            yedekMesaji = (error.localizedDescription, true)
        }
    }

    private func geriYukle(_ y: YedekPaketi, _ kip: YedekServisi.Kip) {
        let o = YedekServisi.geriYukle(y, kip: kip, context)
        bekleyenYedek = nil
        yedekMesaji = ("Geri yüklendi: \(o.metin)" + (o.bekleyen > 0 ? "; \(o.bekleyen) ek beklemede" : ""), false)
    }

    private func levha(_ id: String) -> Levha? {
        try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first
    }

    private var gecerliDosyalar: [PaketKlasoru.Dosya] {
        klasor.dosyalar.filter { if case .gecerli = $0.durum { return true } else { return false } }
    }

    private func iceAktarildiMi(_ d: PaketKlasoru.Dosya) -> Bool {
        guard case .gecerli(let pid, _, _, _, _) = d.durum else { return false }
        return paketler.contains { $0.paket_id == pid }
    }

    private func hepsiniIceAktar() {
        sonuclar = klasor.dosyalar.compactMap { d in
            guard case .gecerli = d.durum, let veri = PaketKlasoru.oku(d.url) else { return nil }
            return PaketIceAktarici.iceAktar(veri: veri, dosyaAdi: d.ad, context: context)
        }
        klasor.tara()
    }

    private func seciliDosyalariAktar(_ urller: [URL]) {
        var yeni: [PaketIceAktarici.Sonuc] = []
        for url in urller {
            let erisim = url.startAccessingSecurityScopedResource()
            defer { if erisim { url.stopAccessingSecurityScopedResource() } }
            guard let veri = PaketKlasoru.oku(url) else {
                yeni.append(.init(dosyaAdi: url.lastPathComponent, basarili: false, paketId: nil,
                                  bulgular: [LintBulgusu("", "dosya okunamadı")], duzenKorunan: []))
                continue
            }
            // Klasöre kopyala ki listede kalsın; hatalıysa da kopyalanır, hata satırı görünsün.
            _ = try? klasor.yaz(veri, ad: url.lastPathComponent)
            yeni.append(PaketIceAktarici.iceAktar(veri: veri, dosyaAdi: url.lastPathComponent, context: context))
        }
        sonuclar = yeni
        klasor.tara()
    }
}

private struct DosyaSatiri: View {
    let dosya: PaketKlasoru.Dosya
    let iceAktarildi: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: simge)
                    .foregroundStyle(renk.kenar)
                Text(dosya.ad)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if iceAktarildi {
                    Text("içe aktarıldı")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RenkSeti.yesil.yazi)
                }
            }
            switch dosya.durum {
            case .indiriliyor:
                Text("iCloud'dan indiriliyor… Biraz sonra aşağı çekip yenile.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tema.ikincil)
            case .gecerli(_, let altKonu, let levha, let soru, let uyarilar):
                Text("\(altKonu) · \(levha) levha · \(soru) soru")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tema.ikincil)
                BulguListesi(bulgular: uyarilar, renk: .sari)
            case .hatali(let bulgular):
                Text("Şema hatası — paket atlanır")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(RenkSeti.kirmizi.yazi)
                BulguListesi(bulgular: bulgular, renk: .kirmizi)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(hatali ? RenkSeti.kirmizi.zemin : Color.white)
    }

    private var hatali: Bool { if case .hatali = dosya.durum { return true } else { return false } }

    private var simge: String {
        switch dosya.durum {
        case .indiriliyor: return "icloud.and.arrow.down"
        case .gecerli: return "doc.text"
        case .hatali: return "exclamationmark.triangle.fill"
        }
    }

    private var renk: RenkSeti {
        switch dosya.durum {
        case .indiriliyor: return .gri
        case .gecerli: return .mavi
        case .hatali: return .kirmizi
        }
    }
}

private struct SonucSatiri: View {
    let sonuc: PaketIceAktarici.Sonuc

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(sonuc.basarili ? "\(sonuc.dosyaAdi) içe aktarıldı" : "\(sonuc.dosyaAdi) atlandı",
                  systemImage: sonuc.basarili ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(sonuc.basarili ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
            if !sonuc.duzenKorunan.isEmpty {
                Text("Düzen korundu: \(sonuc.duzenKorunan.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(RenkSeti.sari.yazi)
            }
            if !sonuc.basarili {
                BulguListesi(bulgular: sonuc.bulgular, renk: .kirmizi)
            }
        }
    }
}

private struct BulguListesi: View {
    let bulgular: [LintBulgusu]
    let renk: RenkSeti
    private let sinir = 6

    var body: some View {
        if !bulgular.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(bulgular.prefix(sinir).enumerated()), id: \.offset) { _, b in
                    Text("• \(b.description)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(renk.yazi)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if bulgular.count > sinir {
                    Text("… \(bulgular.count - sinir) bulgu daha")
                        .font(.system(size: 12))
                        .foregroundStyle(renk.yazi)
                }
            }
        }
    }
}


private struct TaslakSatiri: View {
    let taslak: Taslak
    let levha: Levha?
    let hatalar: [String]?
    let ekle: () -> Void
    @State private var hamAcik = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: taslak.gecerli ? "plus.square.dashed" : "exclamationmark.triangle.fill")
                    .foregroundStyle(taslak.gecerli ? RenkSeti.mavi.kenar : RenkSeti.kirmizi.kenar)
                Text(levha?.baslik ?? taslak.levhaId)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(Bicim.tarih(taslak.tarih)).font(.system(size: 12)).foregroundStyle(Tema.ikincil)
            }
            if let ek = taslak.genisletme, taslak.gecerli {
                Text("\(ek.dugumler.count) düğüm · \((ek.baglantilar ?? []).count) bağlantı: " + ek.dugumler.map(\.etiket).joined(separator: ", "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tema.ikincil)
                if taslak.eklendi {
                    Label("Levhaya eklendi", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RenkSeti.yesil.yazi)
                } else {
                    Button(action: ekle) {
                        Label("Levhaya ekle", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Tema.metin)
                }
                ForEach(hatalar ?? [], id: \.self) {
                    Text("• \($0)").font(.system(size: 12)).foregroundStyle(RenkSeti.kirmizi.yazi)
                }
            } else {
                Text("Şemaya uymadı — ham metin")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(RenkSeti.kirmizi.yazi)
                ForEach(taslak.hatalar.prefix(4), id: \.self) {
                    Text("• \($0)").font(.system(size: 12)).foregroundStyle(RenkSeti.kirmizi.yazi)
                }
                Text(taslak.ham)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Tema.metin)
                    .lineLimit(hamAcik ? nil : 4)
                    .onTapGesture { hamAcik.toggle() }
            }
        }
        .padding(.vertical, 2)
    }
}
