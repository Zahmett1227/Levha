import WidgetKit
import SwiftUI

struct LevhaGirdisi: TimelineEntry {
    let date: Date
    let anlik: WidgetAnligi
    let levha: WidgetLevhasi?
}

/// Saatlik timeline: her saat sıradaki vadeli levha (saat başına sabit, gün içinde dönerek).
struct LevhaSaglayici: TimelineProvider {
    private static let bos = WidgetAnligi(olusturma: .now, tamamlananDakika: 0, planlananDakika: 60, vadeliSayisi: 0, levhalar: [])

    func placeholder(in context: Context) -> LevhaGirdisi {
        LevhaGirdisi(date: .now, anlik: .ornek, levha: WidgetAnligi.ornek.levhalar.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (LevhaGirdisi) -> Void) {
        let a = context.isPreview ? WidgetAnligi.ornek : (WidgetDeposu.oku() ?? .ornek)
        completion(LevhaGirdisi(date: .now, anlik: a, levha: a.levhalar.first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LevhaGirdisi>) -> Void) {
        let a = WidgetDeposu.oku() ?? Self.bos
        let takvim = Calendar.current
        let simdi = Date.now
        let saatBasi = takvim.dateInterval(of: .hour, for: simdi)?.start ?? simdi
        let saat = takvim.component(.hour, from: simdi)
        let girdiler = (0..<12).map { i -> LevhaGirdisi in
            let levha = a.levhalar.isEmpty ? nil : a.levhalar[(saat + i) % a.levhalar.count]
            return LevhaGirdisi(date: i == 0 ? simdi : saatBasi.addingTimeInterval(Double(i) * 3600), anlik: a, levha: levha)
        }
        completion(Timeline(entries: girdiler, policy: .atEnd))
    }
}

// MARK: - Orta: maskeli levha

struct MiniLevha: View {
    let levha: WidgetLevhasi

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * levha.oran)
            let h = w / levha.oran
            let x0 = (geo.size.width - w) / 2, y0 = (geo.size.height - h) / 2
            ZStack(alignment: .topLeading) {
                ForEach(levha.kutular, id: \.id) { k in
                    let r = CGRect(x: x0 + k.x * w, y: y0 + k.y * h, width: k.w * w, height: k.h * h)
                    let kose = k.kose * min(r.width, r.height)
                    let renk = RenkPaleti.hex(k.renk)
                    if k.id == levha.maskeli {
                        RoundedRectangle(cornerRadius: kose, style: .continuous)
                            .fill(Color(hex: 0xF1F3F5))
                            .overlay(RoundedRectangle(cornerRadius: kose, style: .continuous)
                                .strokeBorder(Color(hex: 0x15202B), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                            .overlay(Text("?").font(.system(size: max(9, r.height * 0.6), weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: 0x15202B)).minimumScaleFactor(0.5))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    } else {
                        RoundedRectangle(cornerRadius: kose, style: .continuous)
                            .fill(Color(hex: renk.zemin))
                            .overlay(RoundedRectangle(cornerRadius: kose, style: .continuous)
                                .strokeBorder(Color(hex: renk.kenar), lineWidth: 1))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
        }
    }
}

struct LevhaOrtmeGorunumu: View {
    let girdi: LevhaGirdisi

    var body: some View {
        if let levha = girdi.levha {
            HStack(spacing: 12) {
                MiniLevha(levha: levha)
                    .padding(6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0xDCE2E9), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text("ÖRTME")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: 0x4A5664))
                    Text(levha.baslik)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x15202B))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("? — Dokun")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0x15202B), in: Capsule())
                }
                .frame(width: 112, alignment: .leading)
            }
            .widgetURL(URL(string: "levha://levha/\(levha.id)?mode=ortme"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(Color(hex: 0x2E8B57))
                Text("Vadesi gelen levha yok").font(.system(size: 14, weight: .semibold))
            }
            .widgetURL(URL(string: "levha://bugun"))
        }
    }
}

struct LevhaOrtmeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LevhaOrtme", provider: LevhaSaglayici()) { girdi in
            LevhaOrtmeGorunumu(girdi: girdi)
                .containerBackground(Color(hex: 0xF4F6F8), for: .widget)
        }
        .configurationDisplayName("Levha örtme")
        .description("Vadesi gelen bir levhada tek gizli düğüm. Dokun, Örtme'de aç.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Küçük: bugünün turu

struct BugunGorunumu: View {
    let girdi: LevhaGirdisi

    var body: some View {
        let a = girdi.anlik
        let oran = a.planlananDakika > 0 ? Double(a.tamamlananDakika) / Double(a.planlananDakika) : 0
        VStack(alignment: .leading, spacing: 6) {
            Text("BUGÜN")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color(hex: 0x4A5664))
            ZStack {
                Circle().stroke(Color(hex: 0xDCE2E9), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, oran))
                    .stroke(Color(hex: 0x2E8B57), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(a.tamamlananDakika)")
                        .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    Text("/\(a.planlananDakika) dk")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4A5664))
                }
                .foregroundStyle(Color(hex: 0x15202B))
            }
            .frame(maxWidth: .infinity)
            Text("\(a.vadeliSayisi) levha vadeli")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x15202B))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .widgetURL(URL(string: "levha://bugun"))
    }
}

struct BugunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LevhaBugun", provider: LevhaSaglayici()) { girdi in
            BugunGorunumu(girdi: girdi)
                .containerBackground(Color.white, for: .widget)
        }
        .configurationDisplayName("Bugünün turu")
        .description("Tamamlanan dakika ve vadesi gelen levha sayısı.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct LevhaWidgetPaketi: WidgetBundle {
    var body: some Widget {
        LevhaOrtmeWidget()
        BugunWidget()
    }
}
