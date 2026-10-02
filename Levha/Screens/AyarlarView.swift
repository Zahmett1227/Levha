import SwiftUI

/// Ölçüm › dişli. Model sağlayıcı, soru kırma, sınav dağılımı, yanlış cezası.
struct AyarlarView: View {
    let dersler: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var dagilim = SinavAyarlari.dagilim
    @State private var ceza = SinavAyarlari.ceza
    @State private var saglayici = LLMAyarlari.saglayici
    @State private var tabanURL = LLMAyarlari.apiTabanURL
    @State private var apiAnahtari = LLMAyarlari.apiAnahtari
    @State private var modelAdi = LLMAyarlari.modelAdi
    @State private var maxToken = LLMAyarlari.maxCikisToken
    @AppStorage(SoruKirmaAyari.anahtar) private var soruKirma = true

    private var siraliDersler: [String] {
        let ekstra = Set(dersler + dagilim.keys).subtracting(SinavAyarlari.sira).sorted()
        return SinavAyarlari.sira + ekstra
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LLMSaglayici.allCases) { s in
                        Button {
                            if s.hazir { saglayici = s }
                        } label: {
                            HStack {
                                Text(s.ad).foregroundStyle(s.hazir ? Tema.metin : Tema.cizgi)
                                if !s.hazir { Rozet(metin: "Part 5", renk: .gri) }
                                Spacer()
                                if saglayici == s { Image(systemName: "checkmark").foregroundStyle(Tema.metin) }
                            }
                        }
                        .disabled(!s.hazir)
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
                        TextField("boş", text: $modelAdi)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Stepper(value: $maxToken, in: 100...4000, step: 100) {
                        LabeledContent("Max çıkış token", value: "\(maxToken)")
                    }
                } header: {
                    Text("Model sağlayıcı")
                } footer: {
                    Text("Bu sürümde ağ çağrısı yok: \"Modele sor\", genişletme, Editör değerlendirmesi ve kitap sayfası önerisi sahte istemciyle çevrimdışı çalışır. Alanlar saklanır, Part 5'te kullanılacak. Anahtar yalnız bu cihazın Keychain'inde durur.")
                }

                Section {
                    Toggle("Soru kırma açık", isOn: $soruKirma)
                        .tint(Tema.metin)
                } footer: {
                    Text("Açıkken şıklar 10 saniye kilitli: önce kalıbı ve kökteki belirleyici ipucunu seç.")
                }

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
                    Text("Ders ağırlığı = soru sayısı / 30 (0,3–1,0). Öncelik ve tahmini net bu tabloyu kullanır.")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") {
                        SinavAyarlari.dagilim = dagilim
                        SinavAyarlari.ceza = ceza
                        LLMAyarlari.saglayici = saglayici
                        LLMAyarlari.apiTabanURL = tabanURL.trimmingCharacters(in: .whitespaces)
                        LLMAyarlari.apiAnahtari = apiAnahtari.trimmingCharacters(in: .whitespacesAndNewlines)
                        LLMAyarlari.modelAdi = modelAdi.trimmingCharacters(in: .whitespaces)
                        LLMAyarlari.maxCikisToken = maxToken
                        dismiss()
                    }
                }
            }
        }
    }
}
