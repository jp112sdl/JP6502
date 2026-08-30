import SwiftUI

/// What the tool is printing, as it prints it.
struct ConsoleView: View {
    let runner: ProcessRunner
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Output").font(.headline)
                if runner.isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", systemImage: "stop.fill") { runner.cancel() }
                    .disabled(!runner.isRunning)
                    .help("Send the tool a Ctrl+C")
                Button("Copy", systemImage: "doc.on.doc") {
                    let text = runner.lines.map(\.text).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(runner.lines.isEmpty)
                Button("Clear", systemImage: "trash") { runner.clear() }
                    .disabled(runner.lines.isEmpty || runner.isRunning)
            }
            .labelStyle(.titleOnly)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(runner.lines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .onChange(of: runner.lines.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.none) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func color(for kind: LogLine.Kind) -> Color {
        switch kind {
        case .output: return .primary
        case .error:  return .red
        case .meta:   return .secondary
        }
    }
}

/// A tab: its options above, the log below, two thirds to one third.
///
/// VSplitView would be the obvious thing, but it decides where its divider goes
/// from the ideal heights of what it is given and ignores an idealHeight asking
/// for a share of the window, which is how it ends up halving the tab. The
/// divider here is placed from a fraction instead, and dragging it sets that
/// fraction, so the ratio is what it should be and the split still moves.
struct OptionsAndOutput<Options: View>: View {
    let runner: ProcessRunner
    @ViewBuilder var options: Options

    /// The share of the height the options get.
    @State private var fraction: CGFloat = 2.0 / 3.0
    /// Where the fraction was when the drag started, so a drag reads as one
    /// movement rather than as an accumulation of its own steps.
    @State private var fractionWhenDragBegan: CGFloat?

    private let dividerThickness: CGFloat = 7
    private let smallestOptions: CGFloat = 140
    private let smallestOutput: CGFloat = 100

    var body: some View {
        GeometryReader { geometry in
            let free = max(0, geometry.size.height - dividerThickness)
            VStack(spacing: 0) {
                options
                    .frame(height: height(of: free))
                divider(over: free)
                ConsoleView(runner: runner)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func divider(over free: CGFloat) -> some View {
        ZStack {
            // Wider than the line it draws, so that it can be caught.
            Color.clear.contentShape(Rectangle())
            Divider()
        }
        .frame(height: dividerThickness)
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    let began = fractionWhenDragBegan ?? fraction
                    fractionWhenDragBegan = began
                    guard free > 0 else { return }
                    let wanted = free * began + drag.translation.height
                    fraction = clamp(wanted, in: free) / free
                }
                .onEnded { _ in fractionWhenDragBegan = nil }
        )
    }

    private func height(of free: CGFloat) -> CGFloat {
        clamp(free * fraction, in: free)
    }

    /// Neither half is allowed to be dragged away entirely - and in a window
    /// too short to hold both minimums, the options simply take what there is.
    private func clamp(_ height: CGFloat, in free: CGFloat) -> CGFloat {
        guard free > smallestOptions + smallestOutput else { return free }
        return min(max(height, smallestOptions), free - smallestOutput)
    }
}

/// The line under a tab's options: what will run, and the button that runs it.
struct RunBar: View {
    let title: String
    let systemImage: String
    let runner: ProcessRunner
    var enabled: Bool = true
    var confirm: String?
    let action: () -> Void

    @State private var askingToConfirm = false

    var body: some View {
        HStack {
            Spacer()
            Button {
                if confirm != nil { askingToConfirm = true } else { action() }
            } label: {
                Label(title, systemImage: systemImage)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!enabled || runner.isRunning)
            .confirmationDialog(confirm ?? "", isPresented: $askingToConfirm) {
                Button(title, role: .destructive, action: action)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(confirm ?? "")
            }
        }
    }
}

/// The note a tab shows when the checkout cannot be found.
struct MissingProjectNotice: View {
    var body: some View {
        ContentUnavailableView {
            Label("No project folder", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Pick the JP6502 checkout in Settings. It is the folder that "
                 + "holds Software and FlashPROMv2.")
        }
    }
}
