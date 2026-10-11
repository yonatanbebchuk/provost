import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CertificateView: View {
    @Environment(RunSession.self) private var session
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let cert = session.certificate {
                ScrollView {
                    CertificatePaper(certificate: cert)
                        .frame(width: 680)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .padding(.vertical, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.06))
            } else {
                ProgressView("Issuing certificate…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                if let exportMessage {
                    Text(exportMessage).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let cert = session.certificate {
                    Button("Export PDF…") { exportPDF(cert) }
                        .buttonStyle(MonoProminentButtonStyle())
                        .keyboardShortcut("e", modifiers: .command)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @MainActor
    private func exportPDF(_ cert: Certificate) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(AppConfig.productName)-certificate-\(cert.envId).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // US Letter width at 72 dpi; height follows content.
        let renderer = ImageRenderer(content: CertificatePaper(certificate: cert).frame(width: 612).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        renderer.scale = 2
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        exportMessage = "Saved \(url.lastPathComponent)"
    }
}

/// The printable certificate. Always rendered light-on-white: it is a document, not a screen.
struct CertificatePaper: View {
    let certificate: Certificate

    private let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
    private let muted = Color(red: 0.42, green: 0.42, blue: 0.45)
    private let rule = Color(red: 0.85, green: 0.85, blue: 0.86)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppConfig.productName.uppercased())
                        .font(.system(size: 12, weight: .bold)).kerning(2.2).foregroundStyle(muted)
                    Text("Environment Audit Certificate")
                        .font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(certificate.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    Text(certificate.issuedAt, format: Format.dateTime).font(.system(size: 11)).foregroundStyle(muted)
                }
            }
            .padding(.bottom, 22)

            Rectangle().fill(ink).frame(height: 2).padding(.bottom, 22)

            Text("This certifies that the reinforcement-learning environment below was audited for reward-hacking failure modes, that the listed findings were closed by the referenced patch, and that an adversarial re-run on the patched environment showed no divergence between proxy reward and held-out task quality.")
                .font(.system(size: 12.5, design: .serif)).foregroundStyle(ink)
                .lineSpacing(3)
                .padding(.bottom, 24)

            section("Environment") {
                field("Name", certificate.envName)
                field("Identifier", certificate.envId, mono: true)
                field("Submitted hash", certificate.envHash, mono: true)
                field("Certified hash", certificate.patchedEnvHash, mono: true, strong: true)
            }

            section("Audit run") {
                field("Run", certificate.runId, mono: true)
                field("Policy", "\(certificate.config.model) · \(certificate.config.algorithm)")
                field("Steps", "\(certificate.config.steps) audit + \(certificate.config.steps) verification · seed \(certificate.config.seed)")
            }

            section("Findings closed") {
                VStack(spacing: 0) {
                    ForEach(certificate.findingsClosed) { f in
                        HStack(spacing: 12) {
                            Text(f.id).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(muted).frame(width: 56, alignment: .leading)
                            Text(f.failureMode.displayName).font(.system(size: 12)).foregroundStyle(ink)
                            Spacer()
                            Text(f.severity.displayName.uppercased()).font(.system(size: 9.5, weight: .bold)).kerning(0.5).foregroundStyle(muted)
                            Text("closed").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                        }
                        .padding(.vertical, 6)
                        if f.id != certificate.findingsClosed.last?.id { Rectangle().fill(rule).frame(height: 0.5) }
                    }
                }
            }

            section("Verification") {
                HStack(spacing: 0) {
                    verifyCell("Hack rate", before: certificate.before.hackRate, after: certificate.after.hackRate)
                    Rectangle().fill(rule).frame(width: 0.5, height: 44)
                    verifyCell("Pass rate", before: certificate.before.passRate, after: certificate.after.passRate)
                    Rectangle().fill(rule).frame(width: 0.5, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verdict".uppercased()).font(.system(size: 9.5, weight: .bold)).kerning(0.8).foregroundStyle(muted)
                        Text("Pass").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ink)
                        Text("proxy ≈ true for the whole re-run").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                }
            }

            Rectangle().fill(rule).frame(height: 0.5).padding(.top, 8).padding(.bottom, 16)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Issued by").font(.system(size: 9.5, weight: .bold)).kerning(0.8).foregroundStyle(muted)
                    Text(certificate.issuedBy).font(.system(size: 12)).foregroundStyle(ink)
                    Text("Signature  \(certificate.signature)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(muted)
                        .padding(.top, 4)
                }
                Spacer()
                Image(systemName: "seal")
                    .font(.system(size: 44, weight: .ultraLight)).foregroundStyle(muted)
            }
        }
        .padding(44)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .bold)).kerning(0.8).foregroundStyle(muted)
            content()
        }
        .padding(.bottom, 22)
    }

    private func field(_ label: String, _ value: String, mono: Bool = false, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(muted).frame(width: 110, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11.5, weight: strong ? .semibold : .regular, design: .monospaced) : .system(size: 12, weight: strong ? .semibold : .regular))
                .foregroundStyle(ink)
                .textSelection(.enabled)
        }
    }

    private func verifyCell(_ label: String, before: Double, after: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).kerning(0.8).foregroundStyle(muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.percent(before)).font(.system(size: 18, design: .serif)).foregroundStyle(muted).strikethrough(true, color: muted)
                Text("→").font(.system(size: 14)).foregroundStyle(muted)
                Text(Format.percent(after)).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ink)
            }
            Text("before → after patch").font(.system(size: 10)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 16)
    }
}
