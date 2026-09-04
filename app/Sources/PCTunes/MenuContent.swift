import PCTunesCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: PlayerModel

    @State private var searchQuery = ""
    @State private var isUpNextExpanded = false

    /// While the user is dragging the progress slider, its displayed value comes from
    /// here instead of `model.displayPosition`, so the knob does not fight the
    /// once-a-second interpolation tick mid-drag. Committed with `seek(to:)` on release.
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusArea
            progress
            transport

            Divider()

            volume
            searchField
            upNext
            noticeBanner

            Divider()

            footer
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - What is playing

    @ViewBuilder
    private var statusArea: some View {
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
        } else if !model.extensionConnected {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extension not connected")
                        .font(.headline)
                    Text(model.boundPort.map {
                        "Load the extension in Chrome, then reload the YouTube Music tab. "
                            + "Listening on port \($0)."
                    } ?? "The local server is not listening.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    }

    /// Hidden for a live stream (`duration == 0`), which has no meaningful position.
    @ViewBuilder
    private var progress: some View {
        if let track = model.track, track.duration > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekPosition : model.displayPosition },
                        set: { seekPosition = $0 }
                    ),
                    in: 0...max(track.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            seekPosition = model.displayPosition
                        }
                        isSeeking = editing
                        if !editing {
                            model.seek(to: seekPosition)
                        }
                    }
                )
                HStack {
                    Text(Self.formatTime(isSeeking ? seekPosition : model.displayPosition))
                    Spacer()
                    Text(Self.formatTime(track.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 20) {
            controlButton("backward.fill", action: model.previous)
                .disabled(!model.isConnected)
            controlButton(
                model.track?.playing == true ? "pause.fill" : "play.fill",
                action: model.playPause
            )
            .disabled(!model.extensionConnected)
            controlButton("forward.fill", action: model.next)
                .disabled(!model.isConnected)
            controlButton(thumbsUpSymbol, action: model.like)
                .disabled(!model.extensionConnected)
            controlButton(thumbsDownSymbol, action: model.dislike)
                .disabled(!model.extensionConnected)
        }
        .frame(maxWidth: .infinity)
    }

    /// `liked == nil` means unknown, not neutral — both thumbs stay unlit rather than
    /// implying a rating that was never read.
    private var thumbsUpSymbol: String {
        model.track?.liked == .like ? "hand.thumbsup.fill" : "hand.thumbsup"
    }
    private var thumbsDownSymbol: String {
        model.track?.liked == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown"
    }

    // MARK: - Extras

    /// An unknown volume (`nil`) renders nothing rather than a slider sitting at zero,
    /// which would read as muted.
    @ViewBuilder
    private var volume: some View {
        if let level = model.track?.volume {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { level }, set: { model.setVolume($0) }),
                    in: 0...1
                )
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchField: some View {
        TextField("Search YouTube Music", text: $searchQuery)
            .disabled(!model.extensionConnected)
            .onSubmit {
                model.search(searchQuery)
                searchQuery = ""
            }
    }

    @ViewBuilder
    private var upNext: some View {
        DisclosureGroup("Up next", isExpanded: $isUpNextExpanded) {
            if model.queue.isEmpty {
                Text("Nothing queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.queue.prefix(5).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(item.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        // The list costs nothing while collapsed; only ask for it on expansion.
        .onChange(of: isUpNextExpanded) { _, expanded in
            if expanded {
                model.refreshQueue()
            }
        }
    }

    /// The only way a broken page selector reaches the user, so it needs to read as
    /// legible text rather than being tucked away.
    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(notice)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - App commands

    @ViewBuilder
    private var footer: some View {
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
        // `SettingsLink` opens the `Settings` scene declared in `PCTunesApp` directly —
        // no closure threaded in from the app, and no window management here.
        SettingsLink { Text("Settings…") }
        Button("Quit PC Tunes") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    // MARK: - Helpers

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

    /// `m:ss`, or `h:mm:ss` past an hour.
    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
