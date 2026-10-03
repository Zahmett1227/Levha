import SwiftUI
import SwiftData

// MARK: - Ayrıştırma

/// Anlatımın blok yapısı: başlık, paragraf, madde listesi, alıntı (TUS notu kutusu), tablo, ayraç.
/// Satır içi biçim (kalın, italik, bağlantı) `AttributedString(markdown:)` ile; tablolar kendi çizicimizle.
enum AnlatimAyristirici {
    enum Ham {
        case baslik(seviye: Int, metin: String)
        case paragraf(String)
        case liste([(isaret: String, metin: String)])
        case alinti(String)
        case tablo(baslik: [String], satirlar: [[String]])
        case ayrac
    }

    static func bloklar(_ md: String) -> [Ham] {
        var sonuc: [Ham] = []
        var paragraf: [String] = []
        var liste: [(isaret: String, metin: String)] = []
        var alinti: [String] = []
        var tablo: [String] = []

        func paragrafBitir() { if !paragraf.isEmpty { sonuc.append(.paragraf(paragraf.joined(separator: " "))); paragraf = [] } }
        func listeBitir() { if !liste.isEmpty { sonuc.append(.liste(liste)); liste = [] } }
        func alintiBitir() { if !alinti.isEmpty { sonuc.append(.alinti(alinti.joined(separator: " "))); alinti = [] } }
        func tabloBitir() {
            guard !tablo.isEmpty else { return }
            let satirlar = tablo.map(hucreler).filter { !ayiriciMi($0) }
            if let ilk = satirlar.first {
                let n = ilk.count
                sonuc.append(.tablo(baslik: ilk, satirlar: satirlar.dropFirst().map { s in
                    Array((s + Array(repeating: "", count: max(0, n - s.count))).prefix(n))
                }))
            }
            tablo = []
        }
        func hepsiniBitir() { paragrafBitir(); listeBitir(); alintiBitir(); tabloBitir() }

        for satir in md.components(separatedBy: "\n") {
            let t = satir.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { hepsiniBitir(); continue }
            let diyez = t.prefix { $0 == "#" }.count
            if (1...3).contains(diyez), t.dropFirst(diyez).first == " " {
                hepsiniBitir()
                sonuc.append(.baslik(seviye: diyez, metin: String(t.dropFirst(diyez)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if t == "---" || t == "***" { hepsiniBitir(); sonuc.append(.ayrac); continue }
            if t.hasPrefix("|") { paragrafBitir(); listeBitir(); alintiBitir(); tablo.append(t); continue }
            tabloBitir()
            if t.hasPrefix(">") {
                paragrafBitir(); listeBitir()
                alinti.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            alintiBitir()
            if let madde = madde(t) {
                paragrafBitir()
                liste.append(madde)
                continue
            }
            // Girintili satır önceki maddenin devamıdır.
            if !liste.isEmpty, satir.first == " " || satir.first == "\t" {
                liste[liste.count - 1].metin += " " + t
                continue
            }
            listeBitir()
            paragraf.append(t)
        }
        hepsiniBitir()
        return sonuc
    }

    private static func madde(_ t: String) -> (isaret: String, metin: String)? {
        for onek in ["- ", "* ", "+ "] where t.hasPrefix(onek) { return ("•", String(t.dropFirst(2))) }
        let rakam = t.prefix { $0.isNumber }
        if !rakam.isEmpty, rakam.count <= 3 {
            let kalan = t.dropFirst(rakam.count)
            if kalan.hasPrefix(". ") || kalan.hasPrefix(") ") { return ("\(rakam).", String(kalan.dropFirst(2))) }
        }
        return nil
    }

    private static func hucreler(_ satir: String) -> [String] {
        var s = satir.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func ayiriciMi(_ hucreler: [String]) -> Bool {
        !hucreler.isEmpty && hucreler.allSatisfy { h in
            let c = h.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return c.count >= 3 && c.allSatisfy { $0 == "-" }
        }
    }
}

// MARK: - Referanslar

/// Anlatımdaki `[[...]]` referansının açılacağı yer.
struct LevhaHedefi: Identifiable, Hashable {
    let levhaId: String
    let dugumId: String?
    var id: String { "\(levhaId)#\(dugumId ?? "")" }

    static let sema = "levhaoku"

    var url: URL? {
        var c = URLComponents()
        c.scheme = Self.sema
        c.host = "ac"
        c.queryItems = [URLQueryItem(name: "levha", value: levhaId)] + (dugumId.map { [URLQueryItem(name: "dugum", value: $0)] } ?? [])
        return c.url
    }

    init(levhaId: String, dugumId: String?) {
        self.levhaId = levhaId
        self.dugumId = dugumId
    }

    init?(_ url: URL) {
        guard url.scheme == Self.sema, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let l = c.queryItems?.first(where: { $0.name == "levha" })?.value else { return nil }
        levhaId = l
        dugumId = c.queryItems?.first { $0.name == "dugum" }?.value
    }
}

/// Paketin levhalarına (ve tam id'yle başka paketlerin levhalarına) göre referans çözücü.
@MainActor
struct ReferansCozucu {
    let paket: Paket
    let context: ModelContext
    private let levhalar: [Levha]
    private let ozet: [(id: String, dugumler: Set<String>)]

    init(paket: Paket, context: ModelContext) {
        self.paket = paket
        self.context = context
        levhalar = paket.siraliLevhalar
        ozet = levhalar.map { (id: $0.id, dugumler: Set($0.dugumler.map(\.id))) }
    }

    /// Hedef ve varsayılan görünen metin (düğüm etiketi ya da levha başlığı); çözülemezse nil.
    func coz(_ r: AnlatimMetni.Referans) -> (hedef: LevhaHedefi, etiket: String)? {
        switch AnlatimMetni.coz(r, paketId: paket.paket_id, levhalar: ozet) {
        case .levha(let id):
            return levhalar.first { $0.id == id }.map { (LevhaHedefi(levhaId: id, dugumId: nil), $0.baslik) }
        case .dugum(let l, let d), .belirsiz(let l, let d, _):
            let etiket = levhalar.first { $0.id == l }?.dugumler.first { $0.id == d }?.etiket ?? d
            return (LevhaHedefi(levhaId: l, dugumId: d), etiket)
        case .disPaket(let id):
            guard let levha = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first else { return nil }
            if let d = r.dugum {
                guard let dugum = levha.dugumler.first(where: { $0.id == d }) else { return nil }
                return (LevhaHedefi(levhaId: id, dugumId: d), dugum.etiket)
            }
            return (LevhaHedefi(levhaId: id, dugumId: nil), levha.baslik)
        case .yok:
            return nil
        }
    }

    /// Satır içi markdown → AttributedString; `[[...]]` dokunulabilir bağlantı olur, çözülemeyen düz metin kalır.
    func satirIci(_ metin: String) -> AttributedString {
        var md = metin
        for r in AnlatimMetni.referanslar(metin).reversed() {
            if let c = coz(r), let url = c.hedef.url {
                let gorunen = (r.metin ?? c.etiket).replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                md.replaceSubrange(r.aralik, with: "[\(gorunen)](\(url.absoluteString))")
            } else {
                md.replaceSubrange(r.aralik, with: r.metin ?? r.dugum ?? r.hedef)
            }
        }
        var a = (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(metin)
        for run in a.runs where run.link != nil {
            a[run.range].foregroundColor = RenkSeti.mavi.yazi
            a[run.range].underlineStyle = Text.LineStyle(pattern: .dot, color: RenkSeti.mavi.kenar)
        }
        return a
    }
}

// MARK: - Görünüm

/// Konu anlatımı: tam ekran okuma. `baslik` verilirse o başlıktan açılır (sorudan "Anlatımda oku");
/// verilmezse kalınan yerden. `[[...]]` referansına dokununca levha Keşif'te, düğüm vurgulu açılır.
struct AnlatimView: View {
    let paket: Paket
    var baslik: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("okumaPuntosu") private var punto = 16.0
    @State private var bloklar: [Blok] = []
    @State private var konum: Int?
    @State private var hedef: LevhaHedefi?
    @State private var genislik: CGFloat = 360
    @State private var hazir = false

    struct Blok: Identifiable {
        enum Tur {
            case baslik(seviye: Int, metin: AttributedString, anahtar: String)
            case paragraf(AttributedString)
            case liste([(isaret: String, metin: AttributedString)])
            case alinti(AttributedString)
            case tablo(baslik: [AttributedString], satirlar: [[AttributedString]])
            case ayrac
        }
        let id: Int
        let tur: Tur
    }

    private var konumAnahtari: String { "okumaKonumu.\(paket.paket_id)" }
    private var icindekiler: [(id: Int, metin: String)] {
        bloklar.compactMap { b in
            if case .baslik(let s, let m, _) = b.tur, s == 2 { return (b.id, String(m.characters)) }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { vekil in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: punto * 0.75) {
                        kunye
                        ForEach(bloklar) { b in
                            blokGorunumu(b).id(b.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Tema.kartKose, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Tema.kartKose, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollPosition(id: $konum, anchor: .top)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { genislik = g.size.width }
                        .onChange(of: g.size.width) { genislik = g.size.width }
                })
                .background(Tema.arkaPlan)
                .onAppear { hazirla(vekil) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            ForEach(icindekiler, id: \.id) { h in
                                Button(h.metin) { withAnimation { vekil.scrollTo(h.id, anchor: .top) } }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("İçindekiler")
                        Button { punto = max(13, punto - 1) } label: { Text("A−").font(.system(size: 14, weight: .semibold)) }
                            .accessibilityLabel("Yazıyı küçült")
                        Button { punto = min(24, punto + 1) } label: { Text("A+").font(.system(size: 17, weight: .semibold)) }
                            .accessibilityLabel("Yazıyı büyüt")
                    }
                }
            }
            .navigationTitle("Anlatım")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $hedef) { h in
                if let levha = levha(h.levhaId) {
                    LevhaReferansView(levha: levha, dugumId: h.dugumId)
                } else {
                    ContentUnavailableView("Levha bulunamadı", systemImage: "square.dashed")
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard let h = LevhaHedefi(url) else { return .systemAction }
                hedef = h
                return .handled
            })
        }
        .tint(Tema.metin)
        .onChange(of: konum) {
            // Sorudan bir başlığa açıldıysa kalınan yer değişmez.
            if baslik == nil, hazir, let konum { UserDefaults.standard.set(konum, forKey: konumAnahtari) }
        }
    }

    private func levha(_ id: String) -> Levha? {
        try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == id })).first
    }

    private func hazirla(_ vekil: ScrollViewProxy) {
        guard bloklar.isEmpty else { return }
        let cozucu = ReferansCozucu(paket: paket, context: context)
        bloklar = AnlatimAyristirici.bloklar(paket.anlatim ?? "").enumerated().map { i, ham in
            switch ham {
            case .baslik(let s, let m):
                return Blok(id: i, tur: .baslik(seviye: s, metin: cozucu.satirIci(m), anahtar: AnlatimMetni.baslikAnahtari(m)))
            case .paragraf(let m): return Blok(id: i, tur: .paragraf(cozucu.satirIci(m)))
            case .liste(let l): return Blok(id: i, tur: .liste(l.map { ($0.isaret, cozucu.satirIci($0.metin)) }))
            case .alinti(let m): return Blok(id: i, tur: .alinti(cozucu.satirIci(m)))
            case .tablo(let b, let s): return Blok(id: i, tur: .tablo(baslik: b.map(cozucu.satirIci), satirlar: s.map { $0.map(cozucu.satirIci) }))
            case .ayrac: return Blok(id: i, tur: .ayrac)
            }
        }
        var hedefBlok: Int?
        if let baslik {
            let anahtar = AnlatimMetni.baslikAnahtari(baslik)
            hedefBlok = bloklar.first { b in
                if case .baslik(_, _, let a) = b.tur { return a == anahtar }
                return false
            }?.id
        } else if let kayitli = UserDefaults.standard.object(forKey: konumAnahtari) as? Int, kayitli < bloklar.count {
            hedefBlok = kayitli
        }
        // Yerleşim bitince kaydır.
        DispatchQueue.main.async {
            if let hedefBlok {
                vekil.scrollTo(hedefBlok, anchor: .top)
                konum = hedefBlok
            }
            hazir = true
        }
    }

    /// Kartın başı: alt konu, bölüm, okuma süresi.
    private var kunye: some View {
        let kelime = AnlatimMetni.kelimeSayisi(paket.anlatim ?? "")
        return VStack(alignment: .leading, spacing: 3) {
            Text("KONU ANLATIMI")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Tema.ikincil)
            Text(paket.alt_konu)
                .font(.system(size: punto * 1.45, weight: .heavy))
                .foregroundStyle(Tema.metin)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(paket.ders) › \(paket.bolum) · \(Bicim.sayi(Double(kelime))) kelime · ~\(max(1, kelime / 200)) dk")
                .font(.system(size: 12.5))
                .foregroundStyle(Tema.ikincil)
        }
        .padding(.bottom, 4)
    }

    // MARK: Bloklar

    @ViewBuilder
    private func blokGorunumu(_ b: Blok) -> some View {
        switch b.tur {
        case .baslik(let seviye, let metin, _):
            Text(metin)
                .font(.system(size: punto * (seviye == 1 ? 1.45 : seviye == 2 ? 1.28 : 1.1), weight: seviye == 3 ? .semibold : .bold))
                .foregroundStyle(Tema.metin)
                .padding(.top, seviye == 3 ? 4 : punto * 0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraf(let metin):
            Text(metin)
                .font(.system(size: punto))
                .foregroundStyle(Tema.metin)
                .lineSpacing(punto * 0.25)
                .fixedSize(horizontal: false, vertical: true)
        case .liste(let maddeler):
            VStack(alignment: .leading, spacing: punto * 0.35) {
                ForEach(Array(maddeler.enumerated()), id: \.offset) { _, m in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(m.isaret)
                            .font(.system(size: punto, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Tema.ikincil)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(m.metin)
                            .font(.system(size: punto))
                            .foregroundStyle(Tema.metin)
                            .lineSpacing(punto * 0.2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .alinti(let metin):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(RenkSeti.sari.kenar).frame(width: 3)
                Text(metin)
                    .font(.system(size: punto * 0.94, weight: .medium))
                    .foregroundStyle(Tema.metin)
                    .lineSpacing(punto * 0.2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RenkSeti.sari.zemin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .tablo(let baslik, let satirlar):
            tablo(baslik, satirlar)
        case .ayrac:
            Rectangle().fill(Tema.kartKenar).frame(height: 1).padding(.vertical, 4)
        }
    }

    /// Basit tablo çizici: sütunlar kart genişliğine sığdırılır; sığmazsa (en dar 110 pt) yatay kaydırılır.
    @ViewBuilder
    private func tablo(_ baslik: [AttributedString], _ satirlar: [[AttributedString]]) -> some View {
        let sutun = max(1, baslik.count)
        let kullanilabilir = genislik - 24 - 36
        let w = max(110, kullanilabilir / CGFloat(sutun))
        if w * CGFloat(sutun) <= kullanilabilir + 1 {
            tabloIzgarasi(baslik, satirlar, w)
        } else {
            ScrollView(.horizontal) { tabloIzgarasi(baslik, satirlar, w) }
                .scrollIndicators(.visible)
        }
    }

    private func tabloIzgarasi(_ baslik: [AttributedString], _ satirlar: [[AttributedString]], _ w: CGFloat) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(baslik.enumerated()), id: \.offset) { _, h in
                    hucre(h, genislik: w, baslik: true)
                }
            }
            ForEach(Array(satirlar.enumerated()), id: \.offset) { _, satir in
                GridRow {
                    ForEach(Array(satir.enumerated()), id: \.offset) { _, h in
                        hucre(h, genislik: w, baslik: false)
                    }
                }
            }
        }
        // Satır yüksekliği en uzun hücreye eşitlenir; ızgara ideal yüksekliğinde kalır (kırpılmaz).
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(Tema.kartKenar, lineWidth: 1))
    }

    private func hucre(_ metin: AttributedString, genislik: CGFloat, baslik: Bool) -> some View {
        Text(metin)
            .font(.system(size: punto * 0.86, weight: baslik ? .bold : .regular))
            .foregroundStyle(Tema.metin)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: genislik, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(baslik ? Tema.maskeZemin : Color.white)
            .overlay(Rectangle().stroke(Tema.kartKenar, lineWidth: 0.5))
    }
}

/// Anlatımdan açılan levha: Keşif'in son katmanı, referans düğümü koyu halkalı ve notu açık.
struct LevhaReferansView: View {
    let levha: Levha
    let dugumId: String?
    @State private var secili: String?

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
                                               halkalar: dugumId.map { [$0: .koyu] } ?? [:], dokunulabilir: true)) { id in
                withAnimation(.easeOut(duration: 0.25)) { secili = secili == id ? nil : id }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .levhaKarti()
            NotPaneli {
                if let id = secili, let d = levha.dugumler.first(where: { $0.id == id }) {
                    NotIcerigi(dugum: d)
                } else {
                    PanelBasligi(ust: "KEŞİF", alt: levha.tipAdi)
                    Text("Bir düğüme dokun; notu burada açılır.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tema.ikincil)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Tema.arkaPlan)
        .navigationTitle("Levhada")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if secili == nil { secili = dugumId } }
    }
}

// MARK: - Sorudan anlatıma

/// Sorunun `anlatim_baslik`ının geçtiği anlatım.
struct AnlatimHedefi: Identifiable {
    let paket: Paket
    let baslik: String?
    var id: String { "\(paket.paket_id)|\(baslik ?? "")" }

    /// Arama sırası: sorunun konu paketi (bağlı levhanınki) ve kendi paketi, sonra aynı ders + alt konunun, aynı
    /// ders + bölümün ve aynı dersin anlatımlı konu paketleri.
    @MainActor
    static func bul(_ soru: Soru, _ context: ModelContext) -> AnlatimHedefi? {
        guard let baslik = soru.anlatimBaslik, !baslik.isEmpty else { return nil }
        let anahtar = AnlatimMetni.baslikAnahtari(baslik)
        func iceriyor(_ p: Paket) -> Bool {
            guard let a = p.anlatim else { return false }
            return AnlatimMetni.basliklar(a).contains { AnlatimMetni.baslikAnahtari($0.metin) == anahtar }
        }
        var adaylar = [soru.konuPaketi, soru.paket].compactMap { $0 }
        if let kendi = soru.paket {
            let tum = ((try? context.fetch(FetchDescriptor<Paket>())) ?? []).filter { $0.konuPaketiMi && $0.anlatimVar }
            adaylar += tum.filter { $0.ders == kendi.ders && $0.alt_konu == kendi.alt_konu }
            adaylar += tum.filter { $0.ders == kendi.ders && $0.bolum == kendi.bolum }
            adaylar += tum.filter { $0.ders == kendi.ders }
        }
        return adaylar.first(where: iceriyor).map { AnlatimHedefi(paket: $0, baslik: baslik) }
    }
}

/// Cevaptan sonra "Anlatımda oku · başlık"; başlığı içeren anlatım yüklü değilse soluk not.
struct AnlatimBaglantisi: View {
    let soru: Soru
    @Environment(\.modelContext) private var context
    @State private var acik: AnlatimHedefi?

    var body: some View {
        if let baslik = soru.anlatimBaslik, !baslik.isEmpty {
            if let hedef = AnlatimHedefi.bul(soru, context) {
                Button { acik = hedef } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(RenkSeti.mavi.kenar)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("ANLATIMDA OKU")
                                .font(.system(size: 9.5, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(RenkSeti.mavi.yazi)
                            Text(baslik)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Tema.metin)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RenkSeti.mavi.kenar)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RenkSeti.mavi.zemin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RenkSeti.mavi.kenar, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fullScreenCover(item: $acik) { h in AnlatimView(paket: h.paket, baslik: h.baslik) }
            } else {
                Label("Anlatım: \(baslik) · yüklü anlatımda yok", systemImage: "book.closed")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Tema.ikincil)
            }
        }
    }
}

/// Bağımsız sorunun açıklaması (Mini sınav sonuç listesinden).
struct SoruAciklamasi: View {
    let soru: Soru
    let secilen: Int?
    @Environment(\.dismiss) private var dismiss
    private let harfler = ["A", "B", "C", "D", "E"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(soru.kok)
                        .font(.system(size: 15))
                        .foregroundStyle(Tema.metin)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .levhaKarti()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Doğru: \(harfler[min(soru.dogru, 4)]) · \(soru.secenekler[soru.dogru])", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(RenkSeti.yesil.yazi)
                        if let s = secilen, s != soru.dogru, soru.secenekler.indices.contains(s) {
                            Label("Senin: \(harfler[min(s, 4)]) · \(soru.secenekler[s])", systemImage: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RenkSeti.kirmizi.yazi)
                        }
                        Text(soru.aciklama)
                            .font(.system(size: 14))
                            .foregroundStyle(Tema.metin)
                            .fixedSize(horizontal: false, vertical: true)
                        AnlatimBaglantisi(soru: soru)
                    }
                    .padding(14)
                    .levhaKarti()
                }
                .padding(16)
            }
            .background(Tema.arkaPlan)
            .navigationTitle("Açıklama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}
