import SwiftUI
import SwiftData

/// Modelden beklenen değerlendirme JSON'u.
struct EditorDegerlendirmesi: Codable, Equatable {
    struct Duzeltilmis: Codable, Equatable {
        var kok: String
        var secenekler: [String]
        var dogru: Int
    }
    var puan: Int
    var kalip_uyumu: Bool
    var celdirici: String
    var kok_dili: String
    var uzunluk: String
    var ikinci_cevap: String?
    var oneriler: [String]
    var duzeltilmis: Duzeltilmis?
}

/// Levha sayfasının Editör modu: soru yaz, cihazda ön denetle, modele değerlendirt, Yazdıklarım'a kaydet.
struct EditorView: View {
    let levha: Levha

    @Environment(\.modelContext) private var context
    @State private var kok = ""
    @State private var secenekler = ["", "", "", "", ""]
    @State private var dogru = 0
    @State private var kalip: KalipTipi = .en_olasi_tani
    @State private var kazanimId = ""
    @State private var sonuc: EditorDegerlendirmesi?
    @State private var hamYanit: String?
    @State private var hata: String?
    @State private var calisiyor = false
    @State private var sonOlay: EditorOlayi?
    @State private var kayitMesaji: String?

    static let esikPuan = 70
    private let harfler = ["A", "B", "C", "D", "E"]

    private var kazanimlar: [Kazanim] { levha.paket?.kazanimlar(levha) ?? [] }
    private var klinik: Bool { LevhaLint.vakaKokuMu(kok) }
    private var onDenetim: [OnDenetimSatiri] { OnDenetim.denetle(kok: kok, secenekler: secenekler, dogru: dogru, klinik: klinik) }
    private var formDolu: Bool {
        !kok.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && secenekler.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var kaydedilebilir: Bool {
        formDolu && ((sonuc?.puan ?? 0) >= Self.esikPuan || OnDenetim.temiz(onDenetim))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EditorKarti(baslik: "KÖK", sag: "\(OnDenetim.kelimeSayisi(kok)) kelime") {
                    ZStack(alignment: .topLeading) {
                        if kok.isEmpty {
                            Text("Vaka ve soru cümlesi… (… aşağıdakilerden hangisidir?)")
                                .font(.system(size: 14.5))
                                .foregroundStyle(Tema.cizgi)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $kok)
                            .font(.system(size: 14.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                    }
                }

                EditorKarti(baslik: "ŞIKLAR", sag: "doğru şıkkın harfine dokun") {
                    ForEach(0..<5, id: \.self) { i in
                        HStack(spacing: 10) {
                            Button { dogru = i } label: {
                                Text(harfler[i])
                                    .font(.system(size: 13.5, weight: .heavy))
                                    .foregroundStyle(dogru == i ? Color.white : Tema.metin)
                                    .frame(width: 30, height: 30)
                                    .background(dogru == i ? RenkSeti.yesil.kenar : Tema.maskeZemin, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(harfler[i]) doğru şık")
                            .accessibilityAddTraits(dogru == i ? .isSelected : [])
                            TextField("Şık \(harfler[i])", text: $secenekler[i])
                                .font(.system(size: 14.5))
                        }
                    }
                }

                EditorKarti(baslik: "KALIP VE KAZANIM", sag: nil) {
                    LabeledContent("Kalıp") {
                        Picker("Kalıp", selection: $kalip) {
                            ForEach(KalipTipi.allCases, id: \.self) { Text($0.ad).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Tema.metin)
                    }
                    .font(.system(size: 14.5))
                    LabeledContent("Kazanım") {
                        Picker("Kazanım", selection: $kazanimId) {
                            Text("Seçilmedi").tag("")
                            ForEach(kazanimlar) { k in Text(k.metin).lineLimit(2).tag(k.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(Tema.metin)
                    }
                    .font(.system(size: 14.5))
                    .onChange(of: kazanimId) {
                        if let k = kazanimlar.first(where: { $0.id == kazanimId }), let t = k.kalipTipi { kalip = t }
                    }
                }

                if !kok.isEmpty || secenekler.contains(where: { !$0.isEmpty }) {
                    onDenetimKarti
                }

                HStack(spacing: 10) {
                    PanelDugmesi(baslik: calisiyor ? "Değerlendiriliyor…" : "Değerlendir", renk: .mavi, dolu: false, action: degerlendir)
                        .disabled(!formDolu || calisiyor)
                        .opacity(formDolu ? 1 : 0.5)
                    PanelDugmesi(baslik: "Kaydet", renk: .yesil, dolu: true, action: kaydet)
                        .disabled(!kaydedilebilir)
                        .opacity(kaydedilebilir ? 1 : 0.45)
                }
                if !kaydedilebilir && formDolu {
                    Text("Kaydet: model puanı ≥ \(Self.esikPuan) ya da ön denetim temiz olmalı.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.ikincil)
                }
                if let kayitMesaji {
                    Label(kayitMesaji, systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(RenkSeti.yesil.yazi)
                }
                if let hata {
                    Label(hata, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RenkSeti.kirmizi.yazi)
                }
                if let sonuc { sonucKarti(sonuc) }
                if let hamYanit {
                    EditorKarti(baslik: "MODEL YANITI ŞEMAYA UYMADI", sag: nil) {
                        Text(hamYanit).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(RenkSeti.kirmizi.yazi)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var onDenetimKarti: some View {
        let satirlar = onDenetim
        let temiz = OnDenetim.temiz(satirlar)
        return EditorKarti(baslik: "ÖN DENETİM · CİHAZDA", sag: temiz ? "temiz" : "\(satirlar.filter { !$0.gecti }.count) eksik") {
            ForEach(satirlar) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: s.gecti ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(s.gecti ? RenkSeti.yesil.kenar : RenkSeti.kirmizi.kenar)
                    Text(s.ad).font(.system(size: 13, weight: .semibold)).frame(width: 104, alignment: .leading)
                    Text(s.mesaj).font(.system(size: 12.5)).foregroundStyle(s.gecti ? Tema.ikincil : RenkSeti.kirmizi.yazi)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func sonucKarti(_ s: EditorDegerlendirmesi) -> some View {
        EditorKarti(baslik: "MODEL DEĞERLENDİRMESİ" + (LLMAyarlari.sahteMi ? " · SAHTE" : ""), sag: nil) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(s.puan)")
                    .font(.system(size: 34, weight: .heavy).monospacedDigit())
                    .foregroundStyle(s.puan >= Self.esikPuan ? RenkSeti.yesil.yazi : RenkSeti.kirmizi.yazi)
                Text("/100").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.ikincil)
                Spacer()
                Rozet(metin: s.kalip_uyumu ? "kalıba uygun" : "kalıba uymuyor", renk: s.kalip_uyumu ? .yesil : .kirmizi)
            }
            DegerlendirmeSatiri(ad: "Çeldirici", metin: s.celdirici)
            DegerlendirmeSatiri(ad: "Kök dili", metin: s.kok_dili)
            DegerlendirmeSatiri(ad: "Uzunluk", metin: s.uzunluk)
            if let ikinci = s.ikinci_cevap, !ikinci.isEmpty {
                DegerlendirmeSatiri(ad: "İkinci cevap", metin: ikinci, renk: RenkSeti.kirmizi.yazi)
            }
            if !s.oneriler.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Öneriler").font(.system(size: 12.5, weight: .bold))
                    ForEach(s.oneriler, id: \.self) { Text("• \($0)").font(.system(size: 12.5)) }
                }
                .foregroundStyle(Tema.metin)
            }
            if let d = s.duzeltilmis {
                PanelDugmesi(baslik: "Düzeltilmişi al", renk: .mavi, dolu: false) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        kok = d.kok
                        secenekler = (d.secenekler + Array(repeating: "", count: 5)).prefix(5).map { $0 }
                        dogru = min(max(d.dogru, 0), 4)
                    }
                }
            }
        }
    }

    // MARK: - Eylemler

    private func degerlendir() {
        calisiyor = true
        hata = nil
        hamYanit = nil
        kayitMesaji = nil
        let kazanim = kazanimlar.first { $0.id == kazanimId }
        let istem = IstemSablonlari.editorIstemi(kok: kok, secenekler: secenekler, dogru: dogru, kalip: kalip, kazanim: kazanim, klinik: klinik)
        Task {
            defer { calisiyor = false }
            do {
                let veri = IstemSablonlari.jsonAyikla(try await LLMAyarlari.istemci(.editor).jsonUret(sistem: IstemSablonlari.editorSistemi, istem: istem))
                do {
                    let s = try JSONDecoder().decode(EditorDegerlendirmesi.self, from: veri)
                    withAnimation(.easeOut(duration: 0.25)) { sonuc = s }
                    let olay = EditorOlayi(levhaId: levha.id, puan: s.puan, kaydedildi: false, tarih: .now)
                    context.insert(olay)
                    sonOlay = olay
                    try? context.save()
                } catch {
                    sonuc = nil
                    hamYanit = String(data: veri, encoding: .utf8) ?? "(okunamadı)"
                }
            } catch {
                hata = error.localizedDescription
            }
        }
    }

    private func kaydet() {
        guard kaydedilebilir else { return }
        let paket = Self.kullaniciPaketi(context)
        let kazanim = kazanimlar.first { $0.id == kazanimId }
        let levhaDugumleri = Set(levha.dugumler.map(\.id))
        let id = "k\(Int(Date.now.timeIntervalSince1970))"
        let aciklama = sonuc.map { "Kendi yazdığın soru · editör puanı \($0.puan)." } ?? "Kendi yazdığın soru (ön denetim temiz)."
        let json = SoruJSON(id: id, levha: levha.id, dugumler: kazanim?.dugumler.filter(levhaDugumleri.contains),
                            kok: kok.trimmingCharacters(in: .whitespacesAndNewlines),
                            secenekler: secenekler.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                            dogru: dogru, aciklama: aciklama, aciklama_yolu: nil, celdirici_dugum: nil,
                            kazanim: kazanim?.id, kalip: kalip.rawValue, zorluk: nil, secenek_aile: nil,
                            ipucu_sirasi: nil, kirilimlar: nil)
        let soru = Soru(json, paketId: Paket.kullaniciId, sira: paket.sorular.count)
        soru.kaynakTuru = Paket.kullaniciKaynak
        soru.levhaPaketId = levha.paket?.paket_id
        soru.cozumle(ders: levha.paket?.ders, kazanimKalibi: kazanim?.kalip, kazanimSorulabilirligi: kazanim?.sorulabilirlik)
        context.insert(soru)
        soru.paket = paket
        if let sonOlay, !sonOlay.kaydedildi {
            sonOlay.kaydedildi = true
        } else {
            context.insert(EditorOlayi(levhaId: levha.id, puan: sonuc?.puan, kaydedildi: true, tarih: .now))
        }
        try? context.save()
        TurPlanlayici.soruEkle(soru.kimlik, context)
        OlayDefteri.degisti()
        withAnimation(.easeOut(duration: 0.25)) {
            kayitMesaji = "Kaydedildi · Soru › Yazdıklarım; bugünkü tura eklendi."
            kok = ""
            secenekler = ["", "", "", "", ""]
            dogru = 0
            sonuc = nil
            sonOlay = nil
        }
    }

    /// Editör sorularının paketi; yoksa oluşturulur (dosyası yok, içe aktarmadan etkilenmez).
    static func kullaniciPaketi(_ context: ModelContext) -> Paket {
        let pid = Paket.kullaniciId
        if let p = try? context.fetch(FetchDescriptor<Paket>(predicate: #Predicate { $0.paket_id == pid })).first { return p }
        let p = Paket(paket_id: pid)
        p.sema_surumu = 4
        p.ders = "Yazdıklarım"
        p.bolum = "Editör"
        p.alt_konu = "Yazdıklarım"
        context.insert(p)
        return p
    }
}

private struct EditorKarti<Icerik: View>: View {
    let baslik: String
    let sag: String?
    @ViewBuilder var icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(baslik)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Tema.ikincil)
                Spacer()
                if let sag {
                    Text(sag).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Tema.ikincil)
                }
            }
            icerik
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .levhaKarti()
    }
}

private struct DegerlendirmeSatiri: View {
    let ad: String
    let metin: String
    var renk: Color = Tema.metin

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ad).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Tema.ikincil)
            Text(metin).font(.system(size: 13)).foregroundStyle(renk).fixedSize(horizontal: false, vertical: true)
        }
    }
}
