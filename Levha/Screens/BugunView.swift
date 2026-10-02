import SwiftUI
import SwiftData

enum CalismaYeri: String, CaseIterable, Identifiable {
    case kitapli, kitapsiz, sadeceTekrar
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .kitapli: return "Kitaplı"
        case .kitapsiz: return "Kitapsız"
        case .sadeceTekrar: return "Sadece tekrar"
        }
    }
}

/// Bugün: Günlük Tur (beş blok) + tüm alt konular.
struct BugunView: View {
    @Binding var sekme: Sekme
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var faz
    @AppStorage("calismaYeri") private var varsayilanYer = CalismaYeri.kitapli.rawValue
    @AppStorage("aktifPaketId") private var aktifPaketId = ""
    @Query(sort: [SortDescriptor(\Paket.ders), SortDescriptor(\Paket.bolum), SortDescriptor(\Paket.alt_konu)])
    private var paketler: [Paket]
    @State private var tur: TurDurumu?
    @State private var acikBlok: TurBlogu?
    @State private var kitapAcik = false

    /// Editör'ün "Yazdıklarım" paketi alt konu sayılmaz.
    private var icerikPaketleri: [Paket] { paketler.filter { !$0.kullaniciMi } }

    var body: some View {
        NavigationStack {
            List {
                if let tur {
                    turBolumleri(tur)
                }
                tumAltKonular
            }
            .scrollContentBackground(.hidden)
            .background(Tema.arkaPlan)
            .navigationTitle("Bugün")
        }
        .onAppear(perform: yukle)
        .onChange(of: faz) { if faz == .active { yukle() } }
        .onChange(of: paketler.map(\.paket_id)) { if let tur { TurPlanlayici.planla(tur, context) } }
        .fullScreenCover(item: $acikBlok) { blok in
            if let tur { TurBlokView(blok: blok, tur: tur) }
        }
        .sheet(isPresented: $kitapAcik) {
            if let tur { KitapSayfasiView(tur: tur) }
        }
    }

    /// Gün 04:00'te döner; uygulama öne gelince yeni günün turu açılır.
    private func yukle() {
        let t = TurPlanlayici.bugun(context)
        if tur?.gun != t.gun { tur = t }
    }

    // MARK: - Tur

    @ViewBuilder
    private func turBolumleri(_ tur: TurDurumu) -> some View {
        Section {
            Picker("Çalışma yeri", selection: Binding(
                get: { tur.calismaYeri },
                set: { yeni in
                    tur.calismaYeri = yeni
                    varsayilanYer = yeni
                    TurPlanlayici.planla(tur, context)
                })) {
                ForEach(CalismaYeri.allCases) { Text($0.ad).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Bugün nerede çalışıyorsun?")
        }

        Section {
            let kitapli = tur.calismaYeri == CalismaYeri.kitapli.rawValue
            let kitap = TurPlanlayici.kuyruk(tur).kitap ?? []
            if kitapli && !tur.kisa {
                KitapSayfasiDugmesi(belirgin: true) { kitapAcik = true }
                if kitap.isEmpty {
                    altKonuSecici(tur)
                } else {
                    kitapOzeti(tur, kitap)
                }
            }
            TurOzeti(tamamlanan: TurPlanlayici.tamamlananDakika(tur), planlanan: TurPlanlayici.planlananDakika(tur),
                     kisa: Binding(get: { tur.kisa }, set: { tur.kisa = $0; try? context.save() }))
            let kuyruk = TurPlanlayici.kuyruk(tur)
            ForEach(TurPlanlayici.aktifBloklar(tur)) { blok in
                let ayrinti = blokAyrintisi(blok, kuyruk, tur)
                Button {
                    acikBlok = blok
                } label: {
                    BlokSatiri(blok: blok, ayrinti: ayrinti.metin, tamam: tur.tamamlananlar.contains(blok.rawValue))
                }
                .buttonStyle(.plain)
                .disabled(!ayrinti.acik)
            }
            if !kitapli || tur.kisa {
                if !kitap.isEmpty { kitapOzeti(tur, kitap) }
                KitapSayfasiDugmesi(belirgin: false) { kitapAcik = true }
            }
        } header: {
            Text("Bugünün turu")
        }
    }

    private func blokAyrintisi(_ blok: TurBlogu, _ k: TurKuyrugu, _ tur: TurDurumu) -> (metin: String, acik: Bool) {
        switch blok {
        case .isinma:
            return ("\(blok.modAdi) · \(k.isinma.count) levha", !k.isinma.isEmpty)
        case .yeni:
            if tur.calismaYeri == CalismaYeri.kitapli.rawValue && tur.altKonuPaketId == nil && k.yeni.isEmpty {
                return ("Önce alt konu seç ya da kitap sayfası tara", false)
            }
            if k.yeni.isEmpty { return ("Uygun levha yok", false) }
            return ("\(blok.modAdi) · \(k.yeni.count) levha", true)
        case .soru:
            return ("\(blok.modAdi) · \(k.soru.count) soru", !k.soru.isEmpty)
        case .pekistirme:
            guard let p = k.pekistirme else { return ("Soru bloğundan sonra hesaplanır", false) }
            if p.isEmpty { return ("Yanlış yok, pekiştirme gerekmedi", false) }
            return ("\(blok.modAdi) · \(p.count) levha", true)
        case .kapanis:
            let n = k.kapanis?.count ?? 0
            return (n == 0 ? "Uygun levha yok" : "\(blok.modAdi) · \(n) levha", n > 0)
        }
    }

    /// Kitap sayfasından seçilen levhalar (Kitaplı modda alt konu seçicinin yerine geçer).
    private func kitapOzeti(_ tur: TurDurumu, _ kitap: [String]) -> some View {
        let basliklar = TurPlanlayici.levhalar(kitap, context).map(\.baslik)
        return HStack(spacing: 10) {
            Image(systemName: "book.pages")
                .foregroundStyle(RenkSeti.mavi.kenar)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kitap sayfasından · \(kitap.count) levha")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.metin)
                Text(basliklar.joined(separator: " · "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tema.ikincil)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                TurPlanlayici.kitapTemizle(tur, context)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.cizgi)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kitap sayfası seçimini kaldır")
        }
        .padding(.vertical, 2)
    }

    private func altKonuSecici(_ tur: TurDurumu) -> some View {
        let secili = paketler.first { $0.paket_id == tur.altKonuPaketId }
        return Menu {
            ForEach(dersler, id: \.self) { ders in
                Section(ders) {
                    ForEach(icerikPaketleri.filter { $0.ders == ders }) { p in
                        Button("\(p.bolum) › \(p.alt_konu)") {
                            tur.altKonuPaketId = p.paket_id
                            aktifPaketId = p.paket_id
                            TurPlanlayici.planla(tur, context)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("Alt konu", systemImage: "book")
                    .foregroundStyle(Tema.metin)
                Spacer()
                Text(secili.map { "\($0.bolum) › \($0.alt_konu)" } ?? "Seç")
                    .foregroundStyle(secili == nil ? RenkSeti.mavi.yazi : Tema.ikincil)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.cizgi)
            }
            .font(.system(size: 15))
        }
    }

    // MARK: - Tüm alt konular

    private var tumAltKonular: some View {
        Section {
            if icerikPaketleri.isEmpty {
                Text("Henüz paket yok. İçerik sekmesinden içe aktar.")
                    .foregroundStyle(Tema.ikincil)
            }
            ForEach(icerikPaketleri) { p in
                Button {
                    aktifPaketId = p.paket_id
                    sekme = .levha
                } label: {
                    AltKonuSatiri(paket: p)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Tüm alt konular")
        }
    }

    private var dersler: [String] {
        var gorulen = Set<String>()
        return icerikPaketleri.map(\.ders).filter { gorulen.insert($0).inserted }
    }
}

/// Kitap sayfası eşlemesi; Kitaplı modda öne çıkar.
struct KitapSayfasiDugmesi: View {
    let belirgin: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: belirgin ? 20 : 17, weight: .semibold))
                    .foregroundStyle(belirgin ? Color.white : Tema.metin)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kitap sayfası")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(belirgin ? Color.white : Tema.metin)
                    Text("Sayfanın fotoğrafından levhayı bul")
                        .font(.system(size: 12.5))
                        .foregroundStyle(belirgin ? Color.white.opacity(0.75) : Tema.ikincil)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(belirgin ? Color.white.opacity(0.7) : Tema.cizgi)
            }
            .padding(.vertical, belirgin ? 6 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(belirgin ? Tema.metin : Color.white)
    }
}

struct TurOzeti: View {
    let tamamlanan: Int
    let planlanan: Int
    @Binding var kisa: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Tema.kartKenar, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: planlanan > 0 ? CGFloat(tamamlanan) / CGFloat(planlanan) : 0)
                    .stroke(RenkSeti.yesil.kenar, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: tamamlanan)
                VStack(spacing: 0) {
                    Text("\(tamamlanan)")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Tema.metin)
                    Text("/\(planlanan) dk")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tema.ikincil)
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tamamlanan \(tamamlanan) dakika, toplam \(planlanan)")

            VStack(alignment: .leading, spacing: 6) {
                Text(tamamlanan >= planlanan && planlanan > 0 ? "Bugünün turu tamam" : "Bugünün turu")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Tema.metin)
                Toggle(isOn: $kisa.animation()) {
                    Text("25 dk sürüm (Isınma + Soru)")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.ikincil)
                }
                .tint(Tema.metin)
            }
        }
        .padding(.vertical, 6)
    }
}

struct BlokSatiri: View {
    let blok: TurBlogu
    let ayrinti: String
    let tamam: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tamam ? "checkmark.circle.fill" : blok.simge)
                .font(.system(size: 20))
                .foregroundStyle(tamam ? RenkSeti.yesil.kenar : Tema.metin)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(blok.ad)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                        .strikethrough(tamam, color: Tema.cizgi)
                    Text("\(blok.dakika) dk")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.ikincil)
                    if !blok.hazir {
                        Text("Part 3")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(RenkSeti.gri.yazi)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RenkSeti.gri.zemin, in: Capsule())
                    }
                }
                Text(ayrinti)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.ikincil)
            }
            Spacer()
            if blok.hazir && !tamam {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.cizgi)
            }
        }
        .padding(.vertical, 4)
        .opacity(blok.hazir ? 1 : 0.45)
        .contentShape(Rectangle())
    }
}

struct AltKonuSatiri: View {
    let paket: Paket

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(paket.alt_konu)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tema.metin)
                Text("\(paket.bolum) · \(paket.levhalar.count) levha · \(paket.sonCalisma.map { "Son: \(Bicim.tarih($0))" } ?? "Henüz çalışılmadı")")
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.ikincil)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.cizgi)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Bir tur bloğunu sıraya alınmış levha/sorularla açar; bitince tik işlenir ve Bugün'e döner.
struct TurBlokView: View {
    let blok: TurBlogu
    let tur: TurDurumu

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var levhalar: [Levha] = []
    @State private var biten: Set<String> = []
    @State private var mod: LevhaModu = .kesif
    @State private var yuklendi = false

    var body: some View {
        Group {
            if blok == .soru {
                NavigationStack {
                    SoruOturumuView(baslik: "Soru bloğu", soruIdleri: TurPlanlayici.kuyruk(tur).soru,
                                    ipucuAviIdleri: Set(TurPlanlayici.kuyruk(tur).ipucuAvi ?? [])) {
                        TurPlanlayici.tamamla(.soru, tur, context)
                        dismiss()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) { Button("Bitir") { bitir() } }
                    }
                }
            } else if yuklendi && levhalar.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView("Bu blokta levha yok", systemImage: blok.simge)
                    Button("Kapat") { dismiss() }
                }
            } else {
                // Levha sekmesiyle aynı kap: gizli gezinme çubuklu NavigationStack (güvenli alan doğru hesaplanır).
                NavigationStack {
                    levhaBlogu
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .background(Tema.arkaPlan)
        .onAppear(perform: yukle)
    }

    private var levhaBlogu: some View {
        LevhaPager(levhalar: levhalar, mod: $mod, izinliModlar: blok.izinliModlar, onek: blok.ad, bildir: olay) {
            Text("\(biten.count)/\(levhalar.count)")
                .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                .foregroundStyle(biten.count == levhalar.count ? RenkSeti.yesil.yazi : Tema.ikincil)
            Button("Bitir") { bitir() }
                .font(.system(size: 14, weight: .semibold))
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tema.metin)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Kapat")
        }
    }

    private func yukle() {
        guard !yuklendi else { return }
        let k = TurPlanlayici.kuyruk(tur)
        let idler: [String]
        switch blok {
        case .isinma: idler = k.isinma
        case .yeni: idler = k.yeni
        case .pekistirme: idler = k.pekistirme ?? []
        case .kapanis: idler = k.kapanis ?? []
        case .soru: idler = []
        }
        levhalar = TurPlanlayici.levhalar(idler, context)
        mod = blok.izinliModlar.first ?? .kesif
        yuklendi = true
    }

    private func olay(_ o: LevhaOlayi) {
        switch (blok, o) {
        case (.isinma, .sabotajBitti(let id, _)):
            biten.insert(id)
        case (.yeni, .ortmeKaydedildi(let id)), (.pekistirme, .ortmeKaydedildi(let id)), (.kapanis, .insaBitti(let id)):
            biten.insert(id)
        default:
            break
        }
        if !levhalar.isEmpty && biten.count >= levhalar.count {
            TurPlanlayici.tamamla(blok, tur, context)
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                dismiss()
            }
        }
    }

    private func bitir() {
        TurPlanlayici.tamamla(blok, tur, context)
        dismiss()
    }
}
