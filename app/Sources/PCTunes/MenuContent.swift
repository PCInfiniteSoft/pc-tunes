import PCTunesCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: PlayerModel

    /// Opens the Settings window. Passed in rather than taken from
    /// `@Environment(\.openSettings)` because this view is hosted in an AppKit popover
    /// (see AppDelegate), where that environment value is never delivered.
    let openSettings: () -> Void

    @State private var isUpNextExpanded = false

    /// Small enough that the two of them stack within the height of the track's own
    /// lines, so they cost the title no width it would otherwise have.
    private static let ratingSize = CGSize(width: 24, height: 22)

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
                // The artwork and the title are the two things a person reaches for to
                // get to the page itself, and the dropdown offered no other way there.
                Button(action: model.openYouTubeMusic) {
                    artwork(for: track.artwork)
                }
                .help(Self.openHelp)
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: model.openYouTubeMusic) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help(Self.openHelp)
                    if !track.artist.isEmpty || track.mode != nil {
                        HStack(spacing: 6) {
                            if !track.artist.isEmpty {
                                Text(track.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let mode = track.mode {
                                modeBadge(mode)
                            }
                        }
                    }
                    // YouTube Music reports a single's album as the song's own name, so
                    // for a great many tracks this line would just repeat the title.
                    if !track.album.isEmpty, track.album != track.title {
                        Text(track.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // Beside the track rather than in the transport row: rating is about
                // this song, where the transport is about playback in general.
                VStack(spacing: 2) {
                    controlButton(thumbsUpSymbol, font: .body, size: Self.ratingSize, action: model.like)
                    controlButton(thumbsDownSymbol, font: .body, size: Self.ratingSize, action: model.dislike)
                }
                .disabled(!model.extensionConnected)
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

    @ViewBuilder
    private var upNext: some View {
        // Nothing playing means nothing to be next, so the whole section goes rather
        // than standing there empty — the same as the progress bar and volume slider.
        if model.track != nil {
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
            // The queue advances with the track, so a list left open goes stale the
            // moment the song changes. Ask again — but still only while it is on screen.
            .onChange(of: trackIdentity) { _, _ in
                if isUpNextExpanded {
                    model.refreshQueue()
                }
            }
        }
    }

    /// What counts as "a different track" for the purpose of refreshing the list.
    /// Title alone would miss a queue advancing between two recordings of the same song.
    private var trackIdentity: String {
        guard let track = model.track else { return "" }
        return "\(track.title)\u{1F}\(track.artist)"
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
        Button("Settings…", action: openSettings)
        Button("Quit PC Tunes") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private static let openHelp = "Open YouTube Music"

    /// Says which of a track's two forms is playing. Drawn only when the page said —
    /// YouTube Music serves many tracks as both a song and a music video, of different
    /// lengths, and the widget would otherwise give no sign of which one it had.
    private func modeBadge(_ mode: PlaybackMode) -> some View {
        Text(mode == .song ? "Song" : "Video")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
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

    /// - Parameters:
    ///   - font: the glyph's size. Ratings sit beside the title rather than in the
    ///     transport row, where transport-sized glyphs crowd out the track's name.
    ///   - size: the clickable area, which stays comfortably larger than the glyph.
    private func controlButton(
        _ symbol: String,
        font: Font = .title2,
        size: CGSize = CGSize(width: 40, height: 30),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .frame(width: size.width, height: size.height)
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
