import SwiftUI

/// Yolak: algoritma ızgarası + tipli bağlantılar (→ normal, ⊣ inhibe, + uyarır, kesikli olası).
/// Şekiller: madde (dikdörtgen), süreç (yuvarlak: enzim/ilaç), karar.
/// Keşif katmanları: 1 maddeler, 2 bağlantılar, 3 TUS, 4 notlar.
struct YolakCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        IzgaraCanvas(cizim: cizim, durum: durum, boyut: boyut, stil: .yolak, dokun: dokun)
    }
}
