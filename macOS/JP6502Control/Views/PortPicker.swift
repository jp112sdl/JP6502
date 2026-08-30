import SwiftUI

/// Picks a serial port, and keeps offering the one that was picked even after
/// it has been unplugged - a stale choice with a note beats a selection that
/// silently jumps to another adapter while the cable is out.
struct PortPicker: View {
    @Binding var selection: String
    var label: String = "Port"

    @State private var ports: [SerialPort] = []
    /// Rescanning on a timer is what makes plugging an adapter in show up
    /// without a trip to a menu.
    private let rescan = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Picker(label, selection: $selection) {
            Text("Automatic").tag("")
            ForEach(ports) { port in
                Text(port.display).tag(port.path)
            }
            if !selection.isEmpty && !ports.contains(where: { $0.path == selection }) {
                Text("\((selection as NSString).lastPathComponent) - not connected")
                    .tag(selection)
            }
        }
        .onAppear { ports = SerialPorts.list() }
        .onReceive(rescan) { _ in
            let found = SerialPorts.list()
            if found != ports { ports = found }
        }
    }
}

/// A baud rate, typed or picked. The rate is not a free choice - it has to
/// match the other end - so the presets are the two that do.
struct BaudField: View {
    @Binding var baud: Int
    var presets: [Int] = [9600, 19200, 38400, 57600, 115200, 225000]

    var body: some View {
        HStack(spacing: 2) {
            TextField("Baud", value: $baud, format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 78)
                .multilineTextAlignment(.trailing)
            Menu {
                ForEach(presets, id: \.self) { rate in
                    Button(String(rate)) { baud = rate }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("The rates these tools use")
        }
    }
}

/// A number that may be written as 0x8000, which is how the flash tool's
/// addresses and lengths are usually written.
struct HexField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var width: CGFloat = 100

    var body: some View {
        // The field always sits in a LabeledContent that already names it, and
        // its own label would be a second one squeezed into the width below -
        // which is what wrapped "seconds" over three lines. Hidden, it is still
        // there for VoiceOver.
        TextField(title, text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }
}
