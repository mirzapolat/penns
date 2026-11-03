import SwiftUI

/// First launch: its own screens, so the note stays the note.
struct WelcomeView: View {
    var finish: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Group {
                if step == 0 { intro } else { widgets }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity.combined(with: .offset(x: -24))
            ))
            .id(step)
            Spacer(minLength: 24)

            Button {
                if step == 0 {
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) { step = 1 }
                } else {
                    finish()
                }
            } label: {
                Text(step == 0 ? "Continue" : "Start Writing")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    private var intro: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text("Penns")
                .font(.system(size: 34, weight: .bold))
            Text("One note, always one glance away.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 22) {
                tip("checklist", "Checklists", "Type “- ” at the start of a line. Tap a circle to tick it.")
                tip("hourglass", "Lifespans", "Let a note last today, this week or until a time you pick.")
                tip("archivebox", "Let it go", "Archive when you're done. Pull down to find old notes.")
            }
            .padding(.top, 40)
        }
    }

    private var widgets: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text("Keep it in sight")
                .font(.system(size: 28, weight: .bold))
            Text("Your note can live on the Lock Screen and the Home Screen.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 22) {
                tip("lock", "Lock Screen", "Touch and hold the Lock Screen → Customize → tap below the clock → Penns.")
                tip("square.grid.2x2", "Home Screen", "Touch and hold the Home Screen → Edit → Add Widget → Penns.")
                tip("rectangle.inset.topleft.filled", "Full width", "Tap … → Go Live to show the note across the Lock Screen and in the Dynamic Island.")
                tip("line.horizontal.3", "The faint line", "Shows where the Lock Screen stops. Turn it off in Settings.")
            }
            .padding(.top, 40)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
