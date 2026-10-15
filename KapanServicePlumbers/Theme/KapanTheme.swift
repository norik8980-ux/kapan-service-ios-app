import SwiftUI

/// Brand tokens aligned with kapanservice.com (`globals.css`).
enum KapanTheme {
    static let orange = Color(red: 1.0, green: 0.416, blue: 0.0) // #FF6A00
    static let orangeDeep = Color(red: 0.886, green: 0.345, blue: 0.0) // #E25800
    static let blue = Color(red: 0.106, green: 0.706, blue: 1.0) // #1BB4FF
    static let ink = Color(red: 0.043, green: 0.051, blue: 0.063) // #0B0D10
    static let canvas = Color(red: 0.957, green: 0.969, blue: 0.984) // #F4F7FB
    static let muted = Color(red: 0.353, green: 0.396, blue: 0.451) // #5A6573
    static let border = Color(red: 0.835, green: 0.871, blue: 0.914) // #D5DEE9
    static let destructive = Color(red: 0.839, green: 0.271, blue: 0.271) // #D64545

    static let brandName = "Kapan Service Plumbers"
    static let brandTagline = "Field jobs for the shop"

    /// Soft dual-radial wash matching the site background atmosphere.
    static var canvasGradient: some View {
        ZStack {
            canvas
            RadialGradient(
                colors: [blue.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 320
            )
            RadialGradient(
                colors: [orange.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}
