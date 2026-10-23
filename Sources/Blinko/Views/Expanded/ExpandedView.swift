import SwiftUI

struct ExpandedView: View {
    let vm: NotchViewModel

    var body: some View {
        if vm.isCommandBarActive {
            CommandBarView(vm: vm)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        let headerHeight = max(vm.geometry.notchSize.height, 30)
        let size = vm.shapeSize
        return VStack(spacing: 0) {
            ExpandedHeader(vm: vm)
                .frame(height: headerHeight)
                .minimalChrome()
            // The header stays at true size (it lines up with the notch); the tab content
            // follows the size preset's scale.
            ThemeScaled(size: CGSize(width: size.width, height: max(0, size.height - headerHeight))) {
                VStack(spacing: 0) {
                    TabContent(vm: vm, tab: Preferences.shared.visibleTabs.contains(vm.tab) ? vm.tab : Preferences.shared.visibleTabs[0])
                        .padding(.horizontal, Metrics.openTopRadius + 12)
                        .padding(.top, 10)
                        .padding(.bottom, Preferences.shared.showCredit ? 8 : 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if Preferences.shared.showCredit {
                        CreditFooter().padding(.bottom, 7).minimalChrome()
                    }
                }
            }
        }
    }
}

/// "Designed by OptimaGeeks" — quiet credit line along the bottom edge.
private struct CreditFooter: View {
    private static let mark: NSImage? = Bundle.main.url(forResource: "optimageeks-mark", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://www.optimageeks.com")!)
        } label: {
            HStack(spacing: 4) {
                Text("Designed by")
                    .foregroundStyle(Color.white.opacity(0.5))
                if let mark = Self.mark {
                    Image(nsImage: mark)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 11, height: 11)
                }
                Text("OptimaGeeks")
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("optimageeks.com")
    }
}

private struct TabContent: View {
    let vm: NotchViewModel
    let tab: NotchTab

    var body: some View {
        ZStack(alignment: .top) {
            switch tab {
            case .home: HomeView()
            case .shelf: ShelfView()
            case .clipboard: ClipboardView()
            case .stats: StatsView()
            case .timer: TimerView()
            case .notes: NotesView(vm: vm)
            case .tools: ToolsView(vm: vm)
            }
        }
        .id(tab)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity))
        .animation(Motion.micro, value: tab)
    }
}

// MARK: - Header

private struct ExpandedHeader: View {
    let vm: NotchViewModel
    @Namespace private var tabNS

    var body: some View {
        // Each side of the notch gets half of what is left, so neither the tabs nor the
        // status items can ever slide under the notch (Compact size, many tabs).
        let tabs = Preferences.shared.visibleTabs
        let padding = Theme.shared.openTopRadius + 8
        let gap = vm.geometry.hasNotch ? vm.geometry.notchSize.width + 16 : 16
        let side = max(0, (vm.shapeSize.width - padding * 2 - gap) / 2)
        let tabWidth = min(30, max(22, ((side - 4 - 2 * CGFloat(tabs.count - 1)) / CGFloat(tabs.count)).rounded(.down)))
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    TabButton(tab: tab, selected: vm.tab == tab, namespace: tabNS, width: tabWidth) {
                        withAnimation(Motion.micro) { vm.tab = tab }
                    }
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .frame(maxWidth: side, alignment: .leading)

            Spacer(minLength: gap)

            // With many tabs and every status item on, a 700 pt island runs out of room:
            // drop the weather first, then the time, rather than squeezing text.
            ViewThatFits(in: .horizontal) {
                statusItems(weather: true, time: true)
                statusItems(weather: false, time: true)
                statusItems(weather: false, time: false)
            }
            .frame(maxWidth: side, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.horizontal, padding)
        .padding(.top, 2)
    }

    private func statusItems(weather: Bool, time: Bool) -> some View {
        // Home shows the clock and weather in its own layout already.
        let homeClock = vm.tab == .home && Preferences.shared.showClock
        return HStack(spacing: 4) {
            KeepAwakeIndicator { withAnimation(Motion.micro) { vm.tab = .tools } }
            if weather, !homeClock {
                HeaderWeather()
            }
            if time, Preferences.shared.showClockInHeader, !homeClock {
                TimelineView(.everyMinute) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize()
                        .padding(.trailing, 8)
                }
            }
            HeaderBattery()
            IslandIconButton(symbol: vm.isPinned ? "pin.fill" : "pin", size: 11, plate: 24,
                             tint: vm.isPinned ? Theme.shared.accent : .secondaryText,
                             help: "Keep open") { vm.isPinned.toggle() }
            IslandIconButton(symbol: "gearshape.fill", size: 11, plate: 24, tint: .secondaryText, help: "Settings") {
                vm.close()
                SettingsWindowController.shared.show()
            }
        }
        .fixedSize()
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let namespace: Namespace.ID
    var width: CGFloat = 30
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let theme = Theme.shared
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? theme.onAccent : (hovering ? .primaryText : .secondaryText))
                .frame(width: width, height: 22)
                .background {
                    if selected {
                        Capsule().fill(theme.accent).matchedGeometryEffect(id: "tab", in: namespace)
                    } else if hovering {
                        Capsule().fill(Color.fillSubtle)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}

/// Small cup while Keep Awake holds the display on; opens the Tools tab.
private struct KeepAwakeIndicator: View {
    let action: () -> Void

    var body: some View {
        if KeepAwakeService.shared.isActive {
            IslandIconButton(symbol: "cup.and.saucer.fill", size: 11, plate: 24, tint: .orange,
                             help: "Keep Awake is on", action: action)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

private struct HeaderWeather: View {
    var body: some View {
        if Preferences.shared.weatherEnabled, let report = WeatherService.shared.report {
            HStack(spacing: 4) {
                Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 11))
                Text(Temperature.format(report.temperature))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.trailing, 8)
            .help(WeatherCode.description(report.code))
        }
    }
}

private struct HeaderBattery: View {
    var body: some View {
        let battery = BatteryService.shared
        if Preferences.shared.showBatteryInHeader, battery.hasBattery {
            BatteryGlyph(level: battery.level, charging: battery.isPluggedIn)
                .padding(.trailing, 6)
        }
    }
}
