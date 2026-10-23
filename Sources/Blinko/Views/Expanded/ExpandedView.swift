import SwiftUI

struct ExpandedView: View {
    let vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeader(vm: vm)
                .frame(height: max(vm.geometry.notchSize.height, 30))
            TabContent(tab: Preferences.shared.visibleTabs.contains(vm.tab) ? vm.tab : Preferences.shared.visibleTabs[0])
                .padding(.horizontal, Metrics.openTopRadius + 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct TabContent: View {
    let tab: NotchTab

    var body: some View {
        ZStack(alignment: .top) {
            switch tab {
            case .home: HomeView()
            case .shelf: ShelfView()
            case .clipboard: ClipboardView()
            case .stats: StatsView()
            case .timer: TimerView()
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
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Preferences.shared.visibleTabs) { tab in
                    TabButton(tab: tab, selected: vm.tab == tab, namespace: tabNS) {
                        withAnimation(Motion.micro) { vm.tab = tab }
                    }
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.05)))

            Spacer(minLength: vm.geometry.hasNotch ? vm.geometry.notchSize.width + 16 : 16)

            HStack(spacing: 4) {
                // Hidden on Home when the big clock is already showing.
                if Preferences.shared.showClockInHeader, !(vm.tab == .home && Preferences.shared.showClock) {
                    TimelineView(.everyMinute) { ctx in
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.secondaryText)
                            .padding(.trailing, 8)
                    }
                }
                HeaderBattery()
                IslandIconButton(symbol: vm.isPinned ? "pin.fill" : "pin", size: 11, plate: 24,
                                 tint: vm.isPinned ? .orange : .secondaryText,
                                 help: "Keep open") { vm.isPinned.toggle() }
                IslandIconButton(symbol: "gearshape.fill", size: 11, plate: 24, tint: .secondaryText, help: "Settings") {
                    vm.close()
                    SettingsWindowController.shared.show()
                }
            }
        }
        .padding(.horizontal, Metrics.openTopRadius + 8)
        .padding(.top, 2)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.black : (hovering ? .primaryText : .secondaryText))
                .frame(width: 30, height: 22)
                .background {
                    if selected {
                        Capsule().fill(Color.white).matchedGeometryEffect(id: "tab", in: namespace)
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

private struct HeaderBattery: View {
    var body: some View {
        let battery = BatteryService.shared
        if Preferences.shared.showBatteryInHeader, battery.hasBattery {
            BatteryGlyph(level: battery.level, charging: battery.isPluggedIn)
                .padding(.trailing, 6)
        }
    }
}
