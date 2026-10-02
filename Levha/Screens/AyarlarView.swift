import SwiftUI
import SwiftData

/// Ölçüm › dişli. Model sağlayıcı, soru kırma, A/B deneyi, sınav dağılımı, yanlış cezası.
struct AyarlarView: View {
    let dersler: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var dagilim = SinavAyarlari.dagilim
    @State private var ceza = SinavAyarlari.ceza
    @State private var saglayici = LLMAyarlari.saglayici
    @State private var tabanURL = LLMAyarlari.apiTabanURL
    @State private var apiAnahtari = LLMAyarlari.apiAnahtari
    @State private var modelAdi = UserDefaults.standard.string(forKey: "llmModelAdi") ?? ""
    @State private var bicim = LLMAyarlari.apiBicimi
    @State private var maxToken = LLMAyarlari.maxCikisToken
    @State private var sicaklik = LLMAyarlari.sicaklik
    @State private var muhakeme = LLMAyarlari.muhakeme
    @State private var test: TestDurumu = .yok
    @State private var abSifirlaSor = false
    @AppStorage(SoruKirmaAyari.anahtar) private var soruKirma = true
    @AppStorage("kirmaSuresi") private var kirmaSuresi = 10.0
    private var ab: ABDeneyi { ABDeneyi.ortak }

    enum TestDurumu: Equatable {
        case yok, calisiyor, tamam(String), hata(String)
    }

    private var siraliDersler: [String] {
        let ekstra = Set(dersler + dagilim.keys).subtracting(SinavAyarlari.sira).sorted()
        return SinavAyarlari.sira + ekstra
    }

    private var anahtarYok: Bool { apiAnahtari.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                saglayiciBolumu
                Section {
                    Toggle("Soru kırma açık", isOn: $soruKirma)
                        .tint(Tema.metin)
                    if soruKirma {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Kırma süresi", value: "\(Int(kirmaSuresi)) sn")
                            Slider(value: $kirmaSuresi, in: 5...60, step: 5)
                                .tint(Tema.metin)
                        }
                    }
                } footer: {
                    Text("Açıkken şıklar bu süre kilitli: önce kalıbı ve kökteki belirleyici ipucunu seç.")
                }
                abBolumu
                Section {
                    ForEach(siraliDersler, id: \.self) { ders in
                        Stepper(value: Binding(get: { dagilim[ders] ?? SinavAyarlari.bilinmeyenDers },
                                               set: { dagilim[ders] = $0 }), in: 0...80) {
                            HStack {
                                Text(ders)
                                Spacer()
                                Text("\(dagilim[ders] ?? SinavAyarlari.bilinmeyenDers) soru").monospacedDigit()
                                    .foregroundStyle(Tema.ikincil)
                            }
                        }
                    }
                } header: {
                    Text("Sınav dağılımı")
                } footer: {
                    Text("Ders ağırlığı = soru sayısı / 30 (0,3–1,0). Öncelik, tahmini net ve Mini sınav dağılımı bu tabloyu kullanır.")
                }
                Section("Yanlış cezası") {
                    Picker("Ceza", selection: $ceza) {
                        Text("1/4 (4 yanlış 1 doğruyu götürür)").tag(0.25)
                        Text("1/5").tag(0.2)
                        Text("1/3").tag(1.0 / 3)
                        Text("Yok").tag(0.0)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button("Sınav ayarlarını varsayılana dön") {
                        dagilim = SinavAyarlari.varsayilanDagilim
                        ceza = SinavAyarlari.varsayilanCeza
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti", action: kaydet) }
            }
            .confirmationDialog("Gruplar yeniden atansın mı?", isPresented: $abSifirlaSor, titleVisibility: .visible) {
                Button("Yeniden ata", role: .destructive) { ab.baslat(context) }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Alt konular rastgele yeniden bölünür; deney başlangıç tarihi bugün olur. Eski olaylar silinmez.")
            }
        }
    }

    // MARK: - Sağlayıcı

    private var saglayiciBolumu: some View {
        Section {
            ForEach(LLMSaglayici.allCases) { s in
                Button {
                    saglayici = s
                    test = .yok
                } label: {
                    HStack {
                        Text(s.ad).foregroundStyle(Tema.metin)
                        Spacer()
                        if saglayici == s { Image(systemName: "checkmark").foregroundStyle(Tema.metin) }
                    }
                }
            }
            if saglayici == .openaiUyumlu && anahtarYok {
                uyari("API anahtarı yok: anahtar girilene kadar sahte model kullanılır.")
            } else if LLMAyarlari.sahteyeDondu && saglayici == .sahte {
                uyari("Keychain'de anahtar bulunamadığı için sağlayıcı Sahte'ye döndü.")
            }
            LabeledContent("API taban URL") {
                TextField(LLMAyarlari.varsayilanTabanURL, text: $tabanURL)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            LabeledContent("API anahtarı") {
                SecureField("Keychain'de saklanır", text: $apiAnahtari)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            }
            LabeledContent("Model adı") {
                TextField(LLMAyarlari.varsayilanModel, text: $modelAdi)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Picker("API biçimi", selection: $bicim) {
                ForEach(APIBicimi.allCases) { Text($0 == .chat ? "chat" : "responses").tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Muhakeme", selection: $muhakeme) {
                ForEach(MuhakemeDuzeyi.allCases) { Text($0.ad).tag($0) }
            }
            Stepper(value: $maxToken, in: 100...8000, step: 100) {
                LabeledContent("Max çıkış token", value: muhakeme.pay > 0 ? "\(maxToken) + \(muhakeme.pay) muhakeme" : "\(maxToken)")
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Sıcaklık", value: muhakeme == .yok ? Bicim.sayi(sicaklik) : "muhakemede gönderilmez")
                Slider(value: $sicaklik, in: 0...1, step: 0.1).tint(Tema.metin)
            }
            .disabled(muhakeme != .yok)
            Button {
                baglantiTesti()
            } label: {
                HStack {
                    Label("Bağlantı testi", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if test == .calisiyor { ProgressView() }
                }
            }
            .disabled(anahtarYok || test == .calisiyor)
            switch test {
            case .tamam(let m):
                Label(m, systemImage: "checkmark.circle.fill").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(RenkSeti.yesil.yazi)
            case .hata(let m):
                Label(m, systemImage: "xmark.octagon.fill").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(RenkSeti.kirmizi.yazi)
            default:
                EmptyView()
            }
        } header: {
            Text("Model sağlayıcı")
        } footer: {
            Text("\"OpenAI uyumlu\": /chat/completions ya da /responses uç noktasını konuşan her sağlayıcı. Varsayılan model gpt-5.6-luna. Muhakeme token'ları çıkış sınırından düşer; yanıt boş kalmasın diye düzeye göre pay eklenir. Sıcaklık yalnız muhakeme \"Yok\" iken gönderilir. Anahtar yalnız bu cihazın Keychain'inde durur; yedeğe girmez. Model bir alanı reddederse alan atılıp bir kez yeniden denenir.")
        }
    }

    private func uyari(_ metin: String) -> some View {
        Label(metin, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RenkSeti.sari.yazi)
            .listRowBackground(RenkSeti.sari.zemin)
    }

    private func baglantiTesti() {
        guard let url = URL(string: tabanURL.trimmingCharacters(in: .whitespaces)) else {
            test = .hata("Taban URL geçersiz")
            return
        }
        let model = modelAdi.trimmingCharacters(in: .whitespaces).isEmpty ? LLMAyarlari.varsayilanModel : modelAdi
        let istemci = OpenAIUyumluIstemci(tabanURL: url, anahtar: apiAnahtari.trimmingCharacters(in: .whitespacesAndNewlines),
                                         model: model, bicim: bicim, maxCikis: maxToken, sicaklik: sicaklik, muhakeme: muhakeme, amac: nil)
        test = .calisiyor
        Task {
            do {
                test = .tamam(try await istemci.baglantiTesti())
            } catch {
                test = .hata(error.localizedDescription)
            }
        }
    }

    // MARK: - A/B

    private var abBolumu: some View {
        Section {
            if ab.aktif {
                LabeledContent("Durum", value: ab.baslangic.map { "\(Bicim.tarih($0))'den beri açık" } ?? "açık")
                let metin = ab.gruplar.values.filter { $0 == ABDeneyi.metin }.count
                LabeledContent("Gruplar", value: "\(ab.gruplar.count - metin) levha · \(metin) metin")
                Button("Sıfırla (yeniden ata)") { abSifirlaSor = true }
                Button("Deneyi kapat", role: .destructive) { ab.kapat(context) }
            } else {
                Button("Başlat") { ab.baslat(context) }
            }
        } header: {
            Text("A/B deneyi")
        } footer: {
            Text("Alt konular rastgele iki gruba ayrılır ve sabit kalır: \"metin\" grubunda levhalar düz liste olarak çizilir (renk ve konum yok; Örtme boşluk doldurma, Sabotaj ve İnşa kapalı). Ölçüm › Öğrenme'deki A/B kartı iki grubun 7+ gün sonraki hatırlamasını karşılaştırır.")
        }
    }

    // MARK: - Kaydet

    private func kaydet() {
        SinavAyarlari.dagilim = dagilim
        SinavAyarlari.ceza = ceza
        LLMAyarlari.apiTabanURL = tabanURL.trimmingCharacters(in: .whitespaces)
        LLMAyarlari.apiAnahtari = apiAnahtari.trimmingCharacters(in: .whitespacesAndNewlines)
        LLMAyarlari.modelAdi = modelAdi.trimmingCharacters(in: .whitespaces)
        LLMAyarlari.apiBicimi = bicim
        LLMAyarlari.maxCikisToken = maxToken
        LLMAyarlari.sicaklik = sicaklik
        LLMAyarlari.muhakeme = muhakeme
        if saglayici == .openaiUyumlu && anahtarYok {
            LLMAyarlari.saglayici = .sahte
            LLMAyarlari.sahteyeDondu = true
        } else {
            LLMAyarlari.saglayici = saglayici
            LLMAyarlari.sahteyeDondu = false
        }
        dismiss()
    }
}
