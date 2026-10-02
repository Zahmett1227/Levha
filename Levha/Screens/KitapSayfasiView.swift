import SwiftUI
import SwiftData
import PhotosUI
import Vision

/// Cihazda OCR (Vision). Türkçe tanıma destekleniyorsa tr-TR, değilse otomatik dil.
enum MetinOkuyucu {
    static func oku(_ goruntu: UIImage) async -> String {
        guard let cg = goruntu.cgImage else { return "" }
        let yon = CGImagePropertyOrientation(goruntu.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let istek = VNRecognizeTextRequest()
            istek.recognitionLevel = .accurate
            istek.usesLanguageCorrection = true
            if let diller = try? istek.supportedRecognitionLanguages(), diller.contains("tr-TR") {
                istek.recognitionLanguages = ["tr-TR"]
            } else {
                istek.automaticallyDetectsLanguage = true
            }
            try? VNImageRequestHandler(cgImage: cg, orientation: yon).perform([istek])
            return (istek.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Bugün › Kitap sayfası: fotoğraf → OCR → en iyi 5 levha; seçilenler bugünkü Yeni bloğuna eklenir.
struct KitapSayfasiView: View {
    let tur: TurDurumu

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var goruntu: UIImage?
    @State private var ocr: String?
    @State private var okunuyor = false
    @State private var sonuclar: [EslemeSonucu] = []
    @State private var secili: [String] = []
    @State private var kameraAcik = false
    @State private var fotoSecimi: PhotosPickerItem?
    @State private var modelOnerisi: [String]?
    @State private var modelCalisiyor = false
    @State private var hata: String?

    private var levhalar: [Levha] { TurPlanlayici.siraliLevhalar(context) }
    private static let ornekSayfa = Bundle.main.url(forResource: "test-sayfa", withExtension: "jpg")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button {
                            kameraAcik = true
                        } label: {
                            Label("Kamera", systemImage: "camera")
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        PhotosPicker(selection: $fotoSecimi, matching: .images) {
                            Label("Galeri", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                    }
                    .tint(Tema.metin)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if let url = Self.ornekSayfa, goruntu == nil {
                        Button("Örnek sayfayla dene") {
                            if let g = UIImage(contentsOfFile: url.path) { isle(g) }
                        }
                        .font(.system(size: 14))
                    }
                } footer: {
                    Text("Metin cihazda okunur (Vision); fotoğraf hiçbir yere gönderilmez.")
                }

                if let goruntu {
                    Section {
                        HStack(spacing: 12) {
                            Image(uiImage: goruntu)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            if okunuyor {
                                ProgressView()
                                Text("Metin okunuyor…").foregroundStyle(Tema.ikincil)
                            } else if let ocr {
                                Text("\(SayfaEsleme.kelimeler(ocr).count) kelime okundu")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Tema.ikincil)
                            }
                        }
                    }
                }

                if let ocr, !okunuyor {
                    sonucBolumu(ocr)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.arkaPlan)
            .navigationTitle("Kitap sayfası")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !secili.isEmpty {
                    Button {
                        TurPlanlayici.kitapEkle(secili, tur, context)
                        dismiss()
                    } label: {
                        Text("Bugünkü Yeni bloğuna ekle (\(secili.count))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Tema.metin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .fullScreenCover(isPresented: $kameraAcik) {
                KameraSecici { isle($0) }.ignoresSafeArea()
            }
            .onChange(of: fotoSecimi) {
                guard let oge = fotoSecimi else { return }
                Task {
                    if let veri = try? await oge.loadTransferable(type: Data.self), let g = UIImage(data: veri) { isle(g) }
                }
            }
        }
    }

    @ViewBuilder
    private func sonucBolumu(_ ocr: String) -> some View {
        let sozluk = Dictionary(levhalar.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        Section {
            if SayfaEsleme.eslesmeYok(sonuclar) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Eşleşme yok", systemImage: "questionmark.square.dashed")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RenkSeti.sari.yazi)
                    Text("Hiçbir levha %\(Int(SayfaEsleme.esik * 100))'i geçmedi.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.ikincil)
                    Button {
                        modeleSor(ocr)
                    } label: {
                        Label(modelCalisiyor ? "Soruluyor…" : "Modele sor", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(modelCalisiyor)
                }
            }
            ForEach(sonuclar, id: \.id) { s in
                if let l = sozluk[s.id] { satir(l, yuzde: s.skor) }
            }
        } header: {
            Text("Eşleşen levhalar")
        } footer: {
            Text("Satıra dokun → Keşif'te aç. Daireye dokun → seç; seçilenler bugünkü turun Yeni bloğuna girer.")
        }
        if let modelOnerisi {
            Section(LLMAyarlari.sahteMi ? "Model önerisi · sahte" : "Model önerisi") {
                if modelOnerisi.isEmpty { Text("Model uygun levha bulamadı.").foregroundStyle(Tema.ikincil) }
                ForEach(modelOnerisi, id: \.self) { id in
                    if let l = sozluk[id] { satir(l, yuzde: nil) }
                }
            }
        }
        if let hata {
            Text(hata).font(.system(size: 13)).foregroundStyle(RenkSeti.kirmizi.yazi)
        }
        Section {
            DisclosureGroup("Okunan metin") {
                Text(ocr.isEmpty ? "(metin bulunamadı)" : ocr)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Tema.ikincil)
                    .textSelection(.enabled)
            }
        }
    }

    private func satir(_ l: Levha, yuzde: Double?) -> some View {
        let secildi = secili.contains(l.id)
        return HStack(spacing: 12) {
            Button {
                if secildi { secili.removeAll { $0 == l.id } } else { secili.append(l.id) }
            } label: {
                Image(systemName: secildi ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(secildi ? RenkSeti.yesil.kenar : Tema.cizgi)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(secildi ? "Seçimi kaldır" : "Seç")
            Button {
                UserDefaults.standard.set(l.paket?.paket_id, forKey: "aktifPaketId")
                Yonlendirici.ortak.levhaAc(l.id, mod: .kesif)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.baslik).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.metin)
                        Text("\(l.paket?.alt_konu ?? "") · \(l.tipAdi)").font(.system(size: 12.5)).foregroundStyle(Tema.ikincil)
                    }
                    Spacer()
                    if let yuzde {
                        Text("%\(Int((yuzde * 100).rounded()))")
                            .font(.system(size: 15, weight: .heavy).monospacedDigit())
                            .foregroundStyle(yuzde >= SayfaEsleme.esik ? Tema.metin : Tema.cizgi)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.cizgi)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - İşlem

    private func isle(_ g: UIImage) {
        goruntu = g
        ocr = nil
        sonuclar = []
        secili = []
        modelOnerisi = nil
        hata = nil
        okunuyor = true
        Task {
            let metin = await MetinOkuyucu.oku(g)
            let adaylar = levhalar.map {
                EslemeAdayi(id: $0.id, anahtarKelimeler: $0.anahtarKelimeler, baslik: $0.baslik,
                            etiketler: $0.siraliDugumler.map(\.etiket))
            }
            sonuclar = SayfaEsleme.sirala(adaylar, ocr: metin)
            if let ilk = sonuclar.first, ilk.skor >= SayfaEsleme.esik { secili = [ilk.id] }
            ocr = metin
            okunuyor = false
        }
    }

    private func modeleSor(_ ocr: String) {
        modelCalisiyor = true
        hata = nil
        let istem = IstemSablonlari.eslemeIstemi(ocr: ocr, levhalar: levhalar.map { ($0.id, $0.baslik) })
        let bilinen = Set(levhalar.map(\.id))
        Task {
            defer { modelCalisiyor = false }
            do {
                let veri = IstemSablonlari.jsonAyikla(try await LLMAyarlari.istemci.jsonUret(sistem: IstemSablonlari.eslemeSistemi, istem: istem))
                let idler = try JSONDecoder().decode([String].self, from: veri)
                modelOnerisi = Array(idler.filter(bilinen.contains).prefix(3))
            } catch {
                hata = "Model önerisi okunamadı: \(error.localizedDescription)"
            }
        }
    }
}

/// Kamera (UIImagePickerController). Simülatörde kamera yok; düğme pasif kalır.
struct KameraSecici: UIViewControllerRepresentable {
    var sec: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let ust: KameraSecici
        init(_ ust: KameraSecici) { self.ust = ust }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let g = info[.originalImage] as? UIImage { ust.sec(g) }
            ust.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { ust.dismiss() }
    }
}
