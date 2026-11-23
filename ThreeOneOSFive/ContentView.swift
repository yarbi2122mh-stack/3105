import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var videoMode = true

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if videoMode {
                VideoSplashView()
            } else {
                Group {
                    if horizontalSizeClass == .regular {
                        regularLayout
                    } else {
                        compactLayout
                    }
                }
                .tint(Color.white)
                .imageScale(.small)
                .onChange(of: patchDraftCoordinator.request?.id) { requestID in
                    if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
                }
                .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
                    if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
                }
                .onChange(of: developerModeEnabled) { _ in
                    tabNavigation.reconcileSelection(with: featureVisibility)
                }
                .onAppear {
                    tabNavigation.reconcileSelection(with: featureVisibility)
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showLogs) { LogView() }
                .patchStorePresentation(patchStore)
                .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
            }
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("3105")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title).hidden()
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}


struct VideoSplashView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCards = true
    @State private var showCategories = false
    @State private var playingSlot: String?
    @State private var selectedGame = "ffmax"
    @State private var player: AVPlayer? = {
        guard let url = Bundle.main.url(forResource: "intro", withExtension: "mp4") else { return nil }
        let p = AVPlayer(url: url)
        p.allowsExternalPlayback = false
        return p
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayerContainer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            player.seek(to: .zero)
                            player.play()
                        }
                        NotificationCenter.default.addObserver(
                            forName: UIApplication.didBecomeActiveNotification,
                            object: nil,
                            queue: .main
                        ) { _ in
                            player.play()
                        }
                        player.play()
                    }
            }

            if let slot = playingSlot {
                RemoteVideoView(
                    game: selectedGame,
                    slot: slot,
                    onBack: { playingSlot = nil }
                )
                .ignoresSafeArea()
            } else if showCards {
                GameLaunchCards { game in
                    selectedGame = game
                    showCards = false
                    showCategories = true
                }
                .padding(.horizontal, 24)
            } else if showCategories {
                VStack(spacing: 12) {
                    GameCard(title: "AIM") { playingSlot = "aim" }
                    GameCard(title: "HOLOGRAM") { playingSlot = "hologram" }
                    GameCard(title: "SKIN") { playingSlot = "skin" }
                }
                .padding(.horizontal, 24)
            }

            if !showCards {
                VStack {
                    HStack {
                        Button {
                            showCategories = false
                            showCards = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    Spacer()
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            player?.play()
        }
    }
}

struct VideoPlayerContainer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        self.playerLayer = AVPlayerLayer(player: player)
        self.playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

struct GameLaunchCards: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            GameCard(title: "FREE FIRE MAX") { onSelect("ffmax") }
            GameCard(title: "FREE FIRE NORMAL") { onSelect("ffth") }
        }
    }
}

struct GameCard: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


struct RemoteVideoView: View {
    let game: String
    let slot: String
    let onBack: () -> Void
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var status = "Loading file..."

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(status)
                .foregroundColor(.white)
                .font(.caption)
            VStack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                Spacer()
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let url = URL(string: "https://raw.githubusercontent.com/yarbi2122mh-stack/3105/main/assets/" + game + "/" + slot + ".file")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async { status = "No file for " + slot.uppercased() }
                return
            }
            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(slot + ".3105")
            try? data.write(to: dest)
            DispatchQueue.main.async {
                status = "File ready"
                patchDraftCoordinator.presentImport(dest)
            }
        }.resume()
    }
}
