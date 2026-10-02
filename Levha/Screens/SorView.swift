import SwiftUI
import SwiftData

/// "Modele sor": levha bağlamında sohbet (alt yarı sayfa). Cevap `LLMIstemci.sor` akışından parça parça gelir.
struct SorView: View {
    let levha: Levha
    let seciliDugumId: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var kayitlar: [SorKaydi]
    @State private var girdi = ""
    @State private var bekleyen: String?
    @State private var akan: String?
    @State private var hata: String?
    @State private var gorev: Task<Void, Never>?
    @State private var genisletme: [PersistentIdentifier: GenisletmeDurumu] = [:]
    @State private var notEklenen: Set<PersistentIdentifier> = []
    @FocusState private var odak: Bool

    enum GenisletmeDurumu: Equatable {
        case calisiyor
        case hazir(dugum: Int)
        case gecersiz(ham: String, hatalar: [String])
        case hata(String)
    }

    init(levha: Levha, seciliDugumId: String?) {
        self.levha = levha
        self.seciliDugumId = seciliDugumId
        let id = levha.id
        _kayitlar = Query(filter: #Predicate<SorKaydi> { $0.levhaId == id }, sort: \.tarih)
    }

    private var seciliDugum: Dugum? { seciliDugumId.flatMap { id in levha.dugumler.first { $0.id == id } } }
    /// Levha başına son 20 kayıt görünür.
    private var gorunen: [SorKaydi] { Array(kayitlar.suffix(20)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                baglamSeridi
                if LLMAyarlari.sahteyeDondu {
                    Label("Gerçek sağlayıcı yok: sahte model yanıtlıyor. Anahtar: Ölçüm › ⚙︎ › Model sağlayıcı.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RenkSeti.sari.yazi)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RenkSeti.sari.zemin)
                }
                ScrollViewReader { kaydirici in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if gorunen.isEmpty && bekleyen == nil {
                                Text("Bu levha hakkında bir şey sor. Cevap levhanın başlığı, akılda kalanı, düğümleri ve kazanımlarıyla birlikte modele gider.")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Tema.ikincil)
                                    .padding(.vertical, 8)
                            }
                            ForEach(gorunen) { k in
                                SoruBalonu(metin: k.soru)
                                CevapBalonu(metin: k.cevap)
                                cevapAraclari(k)
                            }
                            if let bekleyen {
                                SoruBalonu(metin: bekleyen)
                                if let akan, !akan.isEmpty {
                                    CevapBalonu(metin: akan + (hata == nil ? " ▍" : ""))
                                } else if hata == nil {
                                    ProgressView().padding(.leading, 12)
                                }
                            }
                            if let hata {
                                HStack(spacing: 8) {
                                    Label(hata, systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(RenkSeti.kirmizi.yazi)
                                    Spacer()
                                    Button("Yeniden dene") { if let b = bekleyen { gonder(b) } }
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .padding(10)
                                .background(RenkSeti.kirmizi.zemin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            Color.clear.frame(height: 1).id("son")
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: akan) { kaydirici.scrollTo("son", anchor: .bottom) }
                    .onChange(of: kayitlar.count) { kaydirici.scrollTo("son", anchor: .bottom) }
                    .onAppear { kaydirici.scrollTo("son", anchor: .bottom) }
                }
                girisAlani
            }
            .background(Tema.arkaPlan)
            .navigationTitle("Modele sor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
        }
        .onDisappear { gorev?.cancel() }
    }

    private var baglamSeridi: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.square").foregroundStyle(Tema.ikincil)
            Text(levha.baslik).lineLimit(1)
            if let d = seciliDugum {
                Text("›").foregroundStyle(Tema.cizgi)
                Text(d.etiket)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RenkSeti.ad(d.renk).zemin, in: Capsule())
            }
            Spacer(minLength: 0)
            if LLMAyarlari.sahteMi { Rozet(metin: "SAHTE", renk: .gri) }
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Tema.metin)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(alignment: .bottom) { Tema.kartKenar.frame(height: 1) }
    }

    private var girisAlani: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Soru yaz…", text: $girdi, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .focused($odak)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
            Button {
                gonder(girdi.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(gonderilebilir ? Tema.metin : Tema.cizgi)
            }
            .disabled(!gonderilebilir)
            .accessibilityLabel("Gönder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Tema.arkaPlan)
    }

    private var gonderilebilir: Bool {
        !girdi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (bekleyen == nil || hata != nil)
    }

    // MARK: - Gönderme

    private func gonder(_ soru: String) {
        guard !soru.isEmpty else { return }
        gorev?.cancel()
        girdi = ""
        bekleyen = soru
        akan = ""
        hata = nil
        let sistem = IstemSablonlari.sorSistemi(levha: levha, seciliDugum: seciliDugum)
        var mesajlar = gorunen.suffix(3).flatMap { [LLMMesaj(rol: "user", icerik: $0.soru), LLMMesaj(rol: "assistant", icerik: $0.cevap)] }
        mesajlar.append(LLMMesaj(rol: "user", icerik: soru))
        let istemci = LLMAyarlari.istemci(.sor)
        gorev = Task {
            do {
                for try await parca in istemci.sor(sistem: sistem, mesajlar: mesajlar) {
                    akan = (akan ?? "") + parca
                }
                guard !Task.isCancelled else { return }
                let cevap = (akan ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                context.insert(SorKaydi(levhaId: levha.id, dugumId: seciliDugumId, soru: soru, cevap: cevap, tarih: .now))
                try? context.save()
                bekleyen = nil
                akan = nil
            } catch {
                guard !Task.isCancelled else { return }
                hata = error.localizedDescription
            }
        }
    }

    // MARK: - Cevap araçları

    @ViewBuilder
    private func cevapAraclari(_ k: SorKaydi) -> some View {
        let id = k.persistentModelID
        HStack(spacing: 8) {
            if notEklenen.contains(id) {
                Label("Not eklendi", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RenkSeti.yesil.yazi)
            } else if let did = k.dugumId, levha.dugumler.contains(where: { $0.id == did }) {
                AracDugmesi(baslik: "Düğüme not olarak ekle", simge: "note.text.badge.plus") { notEkle(k, dugumId: did) }
            } else {
                Menu {
                    ForEach(levha.siraliDugumler) { d in
                        Button(d.etiket) { notEkle(k, dugumId: d.id) }
                    }
                } label: {
                    AracEtiketi(baslik: "Düğüme not olarak ekle", simge: "note.text.badge.plus")
                }
            }
            if TaslakServisi.genisletilebilir(levha) {
                AracDugmesi(baslik: "Bu levhayı genişlet", simge: "plus.square.dashed") { genislet(k) }
                    .disabled(genisletme[id] == .calisiyor)
            }
        }
        if let durum = genisletme[id] {
            genisletmeSatiri(durum)
        }
    }

    @ViewBuilder
    private func genisletmeSatiri(_ durum: GenisletmeDurumu) -> some View {
        switch durum {
        case .calisiyor:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Taslak hazırlanıyor…").font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
            }
        case .hazir(let n):
            HStack {
                Label("Taslak hazır · \(n) düğüm", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(RenkSeti.yesil.yazi)
                Spacer()
                Button("İçerik › Taslaklar") {
                    Yonlendirici.ortak.sekme = .icerik
                    dismiss()
                }
                .font(.system(size: 12.5, weight: .bold))
            }
            .padding(8)
            .background(RenkSeti.yesil.zemin, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .gecersiz(let ham, let hatalar):
            VStack(alignment: .leading, spacing: 4) {
                Label("Şemaya uymadı (Taslaklar'da ham metin olarak duruyor)", systemImage: "xmark.octagon.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(RenkSeti.kirmizi.yazi)
                ForEach(hatalar.prefix(3), id: \.self) { Text("• \($0)").font(.system(size: 11.5)).foregroundStyle(RenkSeti.kirmizi.yazi) }
                Text(ham)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tema.metin)
                    .lineLimit(8)
            }
            .padding(8)
            .background(RenkSeti.kirmizi.zemin, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .hata(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(RenkSeti.kirmizi.yazi)
        }
    }

    private func notEkle(_ k: SorKaydi, dugumId: String) {
        DurumServisi.notEkle(levhaId: levha.id, dugumId: dugumId, metin: k.cevap, context)
        notEklenen.insert(k.persistentModelID)
    }

    private func genislet(_ k: SorKaydi) {
        let id = k.persistentModelID
        genisletme[id] = .calisiyor
        Task {
            do {
                let t = try await TaslakServisi.uret(levha: levha, seciliDugum: k.dugumId, cevap: k.cevap, context)
                genisletme[id] = t.gecerli ? .hazir(dugum: t.genisletme?.dugumler.count ?? 0) : .gecersiz(ham: t.ham, hatalar: t.hatalar)
            } catch {
                genisletme[id] = .hata(error.localizedDescription)
            }
        }
    }
}

// MARK: - Balonlar

private struct SoruBalonu: View {
    let metin: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(metin)
                .font(.system(size: 14.5))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Tema.metin, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct CevapBalonu: View {
    let metin: String

    var body: some View {
        HStack {
            Text(metin)
                .font(.system(size: 14.5))
                .foregroundStyle(Tema.metin)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.kartKenar, lineWidth: 1))
            Spacer(minLength: 32)
        }
    }
}

private struct AracDugmesi: View {
    let baslik: String
    let simge: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { AracEtiketi(baslik: baslik, simge: simge) }
            .buttonStyle(.plain)
    }
}

private struct AracEtiketi: View {
    let baslik: String
    let simge: String

    var body: some View {
        Label(baslik, systemImage: simge)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RenkSeti.mavi.yazi)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(RenkSeti.mavi.zemin, in: Capsule())
    }
}
