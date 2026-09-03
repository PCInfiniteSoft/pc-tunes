import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = model.startupFailure {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let track = model.track {
                HStack(alignment: .top, spacing: 12) {
                    artwork(for: track.artwork)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(2)
                        if !track.artist.isEmpty {
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Not playing")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 20) {
                controlButton("backward.fill", action: model.previous)
                    .disabled(!model.isConnected)
                controlButton(
                    model.track?.playing == true ? "pause.fill" : "play.fill",
                    action: model.playPause
                )
                controlButton("forward.fill", action: model.next)
                    .disabled(!model.isConnected)
            }
            .frame(maxWidth: .infinity)

            Divider()

            Button(model.isConnected ? "Go to YouTube Music" : "Open YouTube Music") {
                model.openYouTubeMusic()
            }
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            if model.loginItemNeedsApproval {
                Text("Waiting for approval in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Quit PC Tunes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private func artwork(for url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 40, height: 30)
                .contentShape(Rectangle())
        }
    }
}
