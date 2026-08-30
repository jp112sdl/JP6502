import SwiftUI

struct ContentView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case build, flash, basic, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .build:    return "Build"
            case .flash:    return "Flash"
            case .basic:    return "BASIC"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .build:    return "hammer"
            case .flash:    return "memorychip"
            case .basic:    return "text.append"
            case .settings: return "gearshape"
            }
        }

        var subtitle: String {
            switch self {
            case .build:    return "make"
            case .flash:    return "FlashPROMv2"
            case .basic:    return "6551 serial"
            case .settings: return ""
            }
        }
    }

    let settings: AppSettings
    let index: ProjectIndex

    @State private var tab: Tab = .build
    @State private var buildRunner = ProcessRunner()
    @State private var flashRunner = ProcessRunner()
    @State private var basicRunner = ProcessRunner()

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { entry in
                NavigationLink(value: entry) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(entry.title)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: entry.systemImage)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail
                .navigationTitle(tab.title)
                .navigationSubtitle(settings.projectRoot.lastPathComponent)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !settings.isProjectRootValid && tab != .settings {
            MissingProjectNotice()
        } else {
            switch tab {
            case .build:
                BuildView(settings: settings, index: index, runner: buildRunner)
            case .flash:
                FlashView(settings: settings, index: index, runner: flashRunner)
            case .basic:
                BasicView(settings: settings, index: index, runner: basicRunner)
            case .settings:
                SettingsView(settings: settings, index: index)
            }
        }
    }
}
