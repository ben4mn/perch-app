import AppKit
import PerchKit
import PerchUI
import SwiftUI

/// Sizes in the Clips pane. The pane gets what the open panel leaves under its header: 262 points tall
/// (312, less the 32-point header row, the 6-point gap and the 12-point foot), or 48 less while a prompt
/// takes a row at the foot, and 732 to 852 points wide. Cards take whatever height is left under the
/// filter row and the group labels, so they fill the pane in both cases.
enum ClipLayout {
    static let headerHeight: CGFloat = 26
    static let headerGap: CGFloat = 12
    static let labelHeight: CGFloat = 13
    static let labelGap: CGFloat = 8
    /// Room under the cards for the lift under the pointer.
    static let liftRoom: CGFloat = 6
    static let cardSpacing: CGFloat = 8
    /// Between two age groups: wide enough to read as a break, quiet enough not to be a line.
    static let groupGap: CGFloat = 26
    static let radius: CGFloat = 12
    /// The tallest a card gets, in the panel without a prompt. Pictures are made for this.
    static let fullHeight: CGFloat = 262 - headerHeight - headerGap - labelHeight - labelGap - liftRoom

    static func width(for kind: ClipKind) -> CGFloat {
        kind == .image ? 212 : 160
    }

    static func cardHeight(paneHeight: CGFloat) -> CGFloat {
        max(paneHeight - headerHeight - headerGap - labelHeight - labelGap - liftRoom, 96)
    }

    /// An image card, filled by its picture.
    static var imageSize: CGSize { CGSize(width: width(for: .image), height: fullHeight) }
    /// The well a file's picture sits in, at its largest.
    static var fileWell: CGSize { CGSize(width: width(for: .file) - 16, height: 112) }
}

// MARK: - The pane

struct ClipsPane: View {
    @ObservedObject var clips: ClipsStore
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var chipSpace

    private var calm: Bool { reduceMotion || level != .full }

    var body: some View {
        Group {
            if !clips.isEnabled {
                off
            } else {
                // Redrawn each minute, so a clip moves from "Last hour" to "Earlier today" while the pane is open.
                TimelineView(.everyMinute) { context in
                    shelf(now: context.date)
                }
            }
        }
        .onAppear { clips.paneAppeared() }
    }

    private var off: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(Ink.accent)
            Text("Recent copies and screenshots, one click away").foregroundStyle(Ink.dim)
            PillButton("Turn on", prominent: true) { clips.isEnabled = true }
            Text("Kept for 24 hours, in memory only. Password-manager items are skipped.").font(.system(size: 10.5)).foregroundStyle(Ink.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func shelf(now: Date) -> some View {
        let chips = clips.shelf.chips(now: now)
        if (chips.first?.count ?? 0) == 0 {
            Text("Copy something, take a screenshot, or drop a file here.")
                .foregroundStyle(Ink.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let filter = clips.shelf.resolved(clips.filter, now: now)
            let sections = clips.shelf.sections(filter, now: now)
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: ClipLayout.headerGap) {
                    header(chips, selected: filter)
                    strip(sections, cardHeight: ClipLayout.cardHeight(paneHeight: geometry.size.height))
                }
            }
        }
    }

    /// Filters on the left; on the right, the rule and a way to forget everything.
    private func header(_ chips: [ClipShelf<ClipPayload>.Chip], selected: ClipFilter) -> some View {
        HStack(spacing: 2) {
            ForEach(chips) { chip in
                ClipFilterChip(title: title(of: chip.filter), count: chip.count, isSelected: chip.filter == selected, namespace: chipSpace) {
                    withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { clips.filter = chip.filter }
                }
            }
            Spacer(minLength: 12)
            Text("Kept for 24 hours").font(.system(size: 10.5)).foregroundStyle(Ink.faint).fixedSize()
            PillButton("Clear") {
                withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { clips.removeAll() }
            }
            .help("Forget every clip. Files stay where they are.")
            .padding(.leading, 8)
        }
        .frame(height: ClipLayout.headerHeight)
    }

    private func title(of filter: ClipFilter) -> String {
        switch filter {
        case .all: return "All"
        case let .kind(kind): return kind.title
        }
    }

    /// One strip, newest first, broken into age groups. It runs under the panel's side padding to the
    /// panel's edge, fading there, while at rest its first card lines up with the filters above.
    private func strip(_ sections: [ClipShelf<ClipPayload>.Section], cardHeight: CGFloat) -> some View {
        let inset = CGFloat(NotchLayout.sidePadding)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ClipLayout.groupGap) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: ClipLayout.labelGap) {
                        Text(section.age.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Ink.dim)
                            .frame(height: ClipLayout.labelHeight)
                        HStack(alignment: .top, spacing: ClipLayout.cardSpacing) {
                            ForEach(section.items) { clip in
                                ClipCard(clip: clip, clips: clips, height: cardHeight)
                                    .transition(.perchPop(reduceMotion: calm))
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(section.age.title)
                }
            }
            .padding(.bottom, ClipLayout.liftRoom)
            .animation(Motion.notch(.arrange, level: level, reduceMotion: reduceMotion), value: sections.flatMap(\.items).map(\.id))
        }
        .contentMargins(.horizontal, inset, for: .scrollContent)
        .defaultScrollAnchor(.leading)
        // The fade covers only the side padding, so at rest nothing is faded; cards fade as they scroll under it.
        // It goes on before the negative padding, so it spans the scroll view and not the pane.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: inset)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: inset)
            }
        }
        .padding(.horizontal, -inset)
    }
}

private struct ClipFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let namespace: Namespace.ID
    var select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title).font(.system(size: 11.5, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? Ink.dim : Ink.faint)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isSelected ? Ink.text : (hovering ? Ink.text.opacity(0.8) : Ink.dim))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                if isSelected {
                    Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "clipFilter", in: namespace)
                } else if hovering {
                    Capsule().fill(Color.white.opacity(0.05))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - A card

/// One clip. A click copies it; it drags out as the real thing; on hover a small button removes it.
private struct ClipCard: View {
    let clip: Clip
    let clips: ClipsStore
    let height: CGFloat
    @ObservedObject private var thumbnail: ClipThumbnail
    @Environment(\.notchMotion) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var copied = false

    init(clip: Clip, clips: ClipsStore, height: CGFloat) {
        self.clip = clip
        self.clips = clips
        self.height = height
        thumbnail = clip.payload.thumbnail
    }

    private var width: CGFloat { ClipLayout.width(for: clip.kind) }
    private var time: String { clip.date.formatted(date: .omitted, time: .shortened) }

    private var isHovered: Bool {
        #if DEBUG
        if clips.debugHoveredID == clip.id { return true }
        #endif
        return hovering
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ClipLayout.radius, style: .continuous)
        Button(action: copy) {
            face
                .frame(width: width, height: height)
                .background(isHovered ? Ink.hover : Ink.raised, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(clip.kind == .image ? 0.1 : 0.05), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PerchPressStyle())
        .overlay(alignment: .topTrailing) {
            if isHovered {
                removeButton.padding(7).transition(.opacity)
            }
        }
        .lift(isHovered && level == .full, scale: 1.02)
        .onHover { value in
            withNotchMotion(.peek, level: level, reduceMotion: reduceMotion) { hovering = value }
        }
        .onDrag { clips.itemProvider(for: clip) } preview: {
            ClipDragPreview(clip: clip, picture: thumbnail.isIcon ? nil : thumbnail.image)
        }
        .contextMenu { menu }
        .help(help)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Copies it")
    }

    @ViewBuilder private var face: some View {
        switch clip.kind {
        case .text: textFace
        case .link: linkFace
        case .image: imageFace
        case .file: fileFace
        }
    }

    // MARK: Faces

    private var textFace: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(clip.payload.summary)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(12)
    }

    @ViewBuilder private var linkFace: some View {
        let link = clip.link
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "link")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Ink.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Ink.accent.opacity(0.14)))
                .padding(.bottom, 10)
            Text(link?.host ?? clip.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(link?.rest ?? "")
                .font(.system(size: 11))
                .lineSpacing(1.5)
                .foregroundStyle(Ink.dim)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer.padding(.top, 8)
        }
        .padding(12)
    }

    private var imageFace: some View {
        ZStack(alignment: .bottom) {
            if let image = thumbnail.image, !thumbnail.isIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                // Still being made, or only an icon could be had.
                picturePlaceholder(icon: thumbnail.image, symbol: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 24)
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.66)], startPoint: .top, endPoint: .bottom)
                .frame(height: 48)
                .allowsHitTesting(false)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                stamp(quiet: Color.white.opacity(0.66))
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
        }
    }

    private var fileFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.24))
                if let image = thumbnail.image, !thumbnail.isIcon {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .padding(10)
                } else {
                    picturePlaceholder(icon: thumbnail.image, symbol: "doc")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                // Two lines kept even for a short name, so every file card's picture is the same size.
                Text(clip.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Ink.text)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                footer
            }
            .padding(.horizontal, 4)
            .padding(.top, 9)
            .padding(.bottom, 4)
        }
        .padding(8)
    }

    /// A file's own icon when there is no picture of it yet, or ever.
    @ViewBuilder private func picturePlaceholder(icon: NSImage?, symbol: String) -> some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
        } else {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Ink.faint)
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            stamp(quiet: Ink.faint)
            Spacer(minLength: 0)
        }
        .frame(height: 13)
    }

    /// The time, or "Copied" for a moment after a click.
    private func stamp(quiet: Color) -> some View {
        HStack(spacing: 3) {
            if copied { Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold)) }
            Text(copied ? "Copied" : time).font(.system(size: 10.5).monospacedDigit())
        }
        .foregroundStyle(copied ? Ink.success : quiet)
        .fixedSize()
    }

    private var removeButton: some View {
        Button {
            withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { clips.remove(clip) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(white: 0.17)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PerchPressStyle())
        .help("Remove")
        .accessibilityLabel("Remove")
    }

    @ViewBuilder private var menu: some View {
        Button("Copy", action: copy)
        if clip.kind == .link { Button("Open Link") { clips.open(clip) } }
        if clip.fileURL != nil { Button("Show in Finder") { clips.showInFinder(clip) } }
        Divider()
        Button("Remove") {
            withNotchMotion(.arrange, level: level, reduceMotion: reduceMotion) { clips.remove(clip) }
        }
    }

    private func copy() {
        clips.copy(clip)
        withNotchMotion(.content, level: level, reduceMotion: reduceMotion) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withNotchMotion(.content, level: level, reduceMotion: reduceMotion) { copied = false }
        }
    }

    private var help: String {
        if let url = clip.fileURL { return url.path }
        if let link = clip.link { return link.url.absoluteString }
        return clip.kind == .text ? String(clip.payload.summary.prefix(240)) : clip.title
    }

    private var accessibilityText: String {
        switch clip.kind {
        case .text: return "Text, \(time): \(clip.payload.summary.prefix(160))"
        case .link: return "Link, \(time): \(clip.link?.host ?? clip.title)"
        case .image: return "\(clip.title), \(time)"
        case .file: return "File, \(time): \(clip.title)"
        }
    }
}

/// What follows the pointer while a clip is dragged out: its picture, or its words.
private struct ClipDragPreview: View {
    let clip: Clip
    let picture: NSImage?

    var body: some View {
        if let picture {
            Image(nsImage: picture)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 140, maxHeight: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.accent)
                Text(clip.link?.host ?? clip.title).font(.system(size: 12)).foregroundStyle(Ink.text).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.16)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.accent.opacity(0.6), lineWidth: 1))
        }
    }

    private var symbol: String {
        switch clip.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}
