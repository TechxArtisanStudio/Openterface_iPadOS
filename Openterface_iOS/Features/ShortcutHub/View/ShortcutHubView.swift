//
//  ShortcutHubView.swift
//  Openterface_iOS
//
//  The Shortcut Hub — manage profiles, categories, shortcuts, and "My Shortcuts".
//  Present as a sheet from ControlsView or FloatingKeyboardView.
//

import SwiftUI
import UniformTypeIdentifiers

struct ShortcutHubView: View {

    @ObservedObject private var profileManager = ShortcutProfileManager.shared
    @ObservedObject private var keyboardManager: KeyboardInputManager
    @ObservedObject var appCoordinator: AppCoordinator

    // Hub navigation
    @State private var mainTab: Int = 0  // 0 = Profiles, 1 = Info

    // App-profiles state
    @State private var selectedProfileID: String?
    @State private var selectedCategoryID: String = ShortcutHubView.myCategoryID
    @State private var myShortcuts: [ShortcutItem] = []
    @State private var showingProfileImporter = false
    @State private var showingCreateProfile   = false
    @State private var newProfileName         = ""

    // Shortcut editor
    @State private var editorContext: ShortcutEditorContext? = nil

    // Delete confirmation for profile category shortcuts
    @State private var deletingShortcut: ShortcutItem? = nil

    // Shortcut display style toggle
    @State private var displayStyle: ShortcutDisplayStyle = .list
    @State private var draggingItem: ShortcutItem? = nil

    private static let myCategoryID  = "my"

    private var targetOS: MacroTargetSystem { appCoordinator.targetOS }

    init(keyboardManager: KeyboardInputManager, appCoordinator: AppCoordinator) {
        _keyboardManager = ObservedObject(wrappedValue: keyboardManager)
        _appCoordinator = ObservedObject(wrappedValue: appCoordinator)
    }

    // MARK: Computed

    private var selectedProfile: ShortcutProfileData? {
        guard let id = selectedProfileID else { return nil }
        return profileManager.allProfiles.first { $0.id == id }
    }

    // MARK: Body

    var body: some View {
        Group {
            if let profile = selectedProfile {
                profileDetailView(profile)
            } else {
                hubShell
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .fileImporter(
            isPresented: $showingProfileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { handleProfileImport($0) }
        .sheet(item: $editorContext) { ctx in
            ShortcutEditorSheet(context: ctx) { savedItem in
                handleEditorSave(savedItem, context: ctx)
                editorContext = nil
            }
        }
        .confirmationDialog(
            "Delete \"\(deletingShortcut?.description ?? "")\"?",
            isPresented: Binding(
                get: { deletingShortcut != nil },
                set: { if !$0 { deletingShortcut = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let shortcut = deletingShortcut, let profileId = selectedProfileID {
                    profileManager.deleteShortcutFromProfile(shortcutId: shortcut.id, inProfileId: profileId)
                    myShortcuts = profileManager.myShortcuts(for: profileId)
                }
                deletingShortcut = nil
            }
            Button("Cancel", role: .cancel) { deletingShortcut = nil }
        }
        .onChange(of: selectedProfileID) {
            loadMyShortcuts()
            selectedCategoryID = Self.myCategoryID
        }
        .onChange(of: myShortcuts) {
            saveMyShortcuts()
        }
    }

    // MARK: - Hub Shell

    private var hubShell: some View {
        VStack(spacing: 0) {
            hubHeader
            hubTabBar
            Divider()
            switch mainTab {
            case 0:  profilesTabContent
            case 1:  infoTabContent
            default: EmptyView()
            }
        }
    }

    private var hubHeader: some View {
        HStack(spacing: 8) {
            Text("Shortcut Hub")
                .font(.system(size: 22, weight: .bold))
            if let active = profileManager.activeProfile {
                Text(active.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var hubTabBar: some View {
        let tabs = ["Profiles", "Info"]
        return HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { idx in
                Button { mainTab = idx } label: {
                    Text(tabs[idx])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mainTab == idx ? Color.accentColor : Color.clear)
                        .foregroundColor(mainTab == idx ? .white : .secondary)
                        .animation(.easeInOut(duration: 0.15), value: mainTab)
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Tab 0: Profiles

    private var profilesTabContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    newProfileName = ""
                    showingCreateProfile = true
                } label: {
                    Label("Create Profile", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showingProfileImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            Divider()

            if profileManager.allProfiles.isEmpty {
                Spacer()
                Text("No profiles yet.\nUse Create or Import to add one.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                Spacer()
            } else {
                List {
                    ForEach(profileManager.allProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == profileManager.activeProfileId
                        ) {
                            selectedProfileID = profile.id
                        } onShare: {
                            shareProfile(profile)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color(UIColor.systemBackground))
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert("New Profile", isPresented: $showingCreateProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { profileManager.createUserProfile(name: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Profile Detail

    @ViewBuilder
    private func profileDetailView(_ profile: ShortcutProfileData) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                detailHeaderBar(profile: profile)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    let catCount = profile.categories.count
                    let scCount  = profile.categories.reduce(0) { $0 + $1.shortcuts.count }
                    Text("\(catCount) \(catCount == 1 ? "category" : "categories") · \(scCount) shortcuts")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                categoryTabBar(profile: profile)

                Divider()

                if selectedCategoryID == ShortcutHubView.myCategoryID {
                    myShortcutsListView
                } else if let cat = profile.categories.first(where: { $0.id == selectedCategoryID }) {
                    browseShortcutsListView(category: cat, profile: profile)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }

    private func detailHeaderBar(profile: ShortcutProfileData) -> some View {
        HStack {
            Button("← Back") { selectedProfileID = nil }
                .buttonStyle(.borderless)
                .padding(.leading, 16)

            Spacer()

            // Toggle list / card view
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayStyle = displayStyle == .list ? .card : .list
                }
            } label: {
                Image(systemName: displayStyle == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)

            Button {
                showAddShortcutEditor(profile: profile)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Shortcut")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func categoryTabBar(profile: ShortcutProfileData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryTabPill(id: ShortcutHubView.myCategoryID, label: "⭐ My")
                ForEach(profile.categories) { cat in
                    categoryTabPill(id: cat.id, label: cat.name,
                                    color: hubColorFromHex(cat.colorHex))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    private func categoryTabPill(id: String, label: String, color: Color = .accentColor) -> some View {
        Button { selectedCategoryID = id } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedCategoryID == id ? color : Color.gray.opacity(0.18))
                .foregroundColor(selectedCategoryID == id ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: My Shortcuts list

    private var myShortcutsListView: some View {
        Group {
            if myShortcuts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.square.on.square")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Tap the bookmark icon in a category tab to add shortcuts here, or use + Add Shortcut.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayStyle == .card {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(myShortcuts) { shortcut in
                            let bookmarked = myShortcuts.contains(shortcut)
                            ShortcutCardView(
                                shortcut: shortcut,
                                isDragging: false,
                                trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                                trailingColor: bookmarked ? .accentColor : .secondary,
                                trailingAction: {
                                    if bookmarked { removeFromMyShortcuts(shortcut) }
                                    else          { addToMyShortcuts(shortcut) }
                                },
                                onTap: { executeShortcut(shortcut) },
                                onEdit: nil,
                                appCoordinator: appCoordinator
                            )
                        }
                    }
                    .padding(12)
                }
            } else {
                List {
                    ForEach(myShortcuts) { shortcut in
                        let bookmarked = myShortcuts.contains(shortcut)
                        ShortcutListRow(
                            shortcut: shortcut,
                            trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                            trailingColor: bookmarked ? .accentColor : .secondary,
                            trailingAction: {
                                if bookmarked { removeFromMyShortcuts(shortcut) }
                                else          { addToMyShortcuts(shortcut) }
                            },
                            onTap: { executeShortcut(shortcut) },
                            appCoordinator: appCoordinator
                        )
                        .listRowBackground(Color(UIColor.systemBackground))
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { openMyEditor(shortcut: shortcut) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { from, to in myShortcuts.move(fromOffsets: from, toOffset: to) }
                    .onDelete { myShortcuts.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: Browse list

    private func browseShortcutsListView(category: ShortcutCategoryData,
                                         profile: ShortcutProfileData) -> some View {
        let isUser = profileManager.isUserProfile(id: profile.id)
        if displayStyle == .card {
            return AnyView(
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(category.shortcuts) { shortcut in
                            let bookmarked = myShortcuts.contains(shortcut)
                            ShortcutCardView(
                                shortcut: shortcut,
                                isDragging: false,
                                trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                                trailingColor: bookmarked ? .accentColor : .secondary,
                                trailingAction: {
                                    if bookmarked { removeFromMyShortcuts(shortcut) }
                                    else          { addToMyShortcuts(shortcut) }
                                },
                                onTap: { executeShortcut(shortcut) },
                                onEdit: isUser ? { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } : nil,
                                appCoordinator: appCoordinator
                            )
                            .contextMenu {
                                browseContextMenu(shortcut: shortcut, bookmarked: bookmarked,
                                                  isUser: isUser, profile: profile, category: category)
                            }
                        }
                    }
                    .padding(12)
                }
            )
        } else {
            return AnyView(
                List {
                    ForEach(category.shortcuts) { shortcut in
                        let bookmarked = myShortcuts.contains(shortcut)
                        ShortcutListRow(
                            shortcut: shortcut,
                            trailingIcon: bookmarked ? "bookmark.fill" : "bookmark",
                            trailingColor: bookmarked ? .accentColor : .secondary,
                            trailingAction: {
                                if bookmarked { removeFromMyShortcuts(shortcut) }
                                else          { addToMyShortcuts(shortcut) }
                            },
                            onTap: { executeShortcut(shortcut) },
                            appCoordinator: appCoordinator
                        )
                        .listRowBackground(Color(UIColor.systemBackground))
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if isUser {
                                Button { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isUser {
                                Button(role: .destructive) { deletingShortcut = shortcut } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .contextMenu {
                            browseContextMenu(shortcut: shortcut, bookmarked: bookmarked,
                                             isUser: isUser, profile: profile, category: category)
                        }
                    }
                }
                .listStyle(.plain)
            )
        }
    }

    // MARK: Context menus

    private func browseContextMenu(shortcut: ShortcutItem,
                                   bookmarked: Bool,
                                   isUser: Bool,
                                   profile: ShortcutProfileData,
                                   category: ShortcutCategoryData) -> some View {
        Group {
            Button { executeShortcut(shortcut) } label: { Label("Run", systemImage: "play.fill") }
            if bookmarked {
                Button { removeFromMyShortcuts(shortcut) } label: { Label("Remove from My", systemImage: "bookmark.slash") }
            } else {
                Button { addToMyShortcuts(shortcut) } label: { Label("Add to My", systemImage: "bookmark") }
            }
            if isUser {
                Divider()
                Button { openBrowseEditor(profile: profile, category: category, shortcut: shortcut) } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) { deletingShortcut = shortcut } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Shortcut editor helpers

    private func showAddShortcutEditor(profile: ShortcutProfileData) {
        let useCategory = selectedCategoryID != ShortcutHubView.myCategoryID
                          && profileManager.isUserProfile(id: profile.id)
        editorContext = ShortcutEditorContext(
            profileId: profile.id,
            categoryId: useCategory ? selectedCategoryID : nil,
            existing: nil,
            source: useCategory ? .category : .myShortcuts
        )
    }

    private func handleEditorSave(_ item: ShortcutItem, context: ShortcutEditorContext) {
        let isEdit = context.existing != nil
        switch context.source {
        case .myShortcuts:
            if isEdit {
                myShortcuts = myShortcuts.map { $0.id == item.id ? item : $0 }
            } else {
                if !myShortcuts.contains(item) {
                    myShortcuts.append(item)
                }
            }
        case .category:
            if isEdit {
                profileManager.updateShortcutInProfile(item, inProfileId: context.profileId)
                myShortcuts = profileManager.myShortcuts(for: context.profileId)
            } else {
                profileManager.addShortcut(item, toCategoryId: context.categoryId, inProfileId: context.profileId)
            }
        }
    }

    private func openMyEditor(shortcut: ShortcutItem) {
        editorContext = ShortcutEditorContext(
            profileId: selectedProfileID ?? "", categoryId: nil, existing: shortcut, source: .myShortcuts)
    }

    private func openBrowseEditor(profile: ShortcutProfileData, category: ShortcutCategoryData, shortcut: ShortcutItem) {
        editorContext = ShortcutEditorContext(profileId: profile.id, categoryId: category.id, existing: shortcut, source: .category)
    }

    // MARK: - Helper actions

    private func addToMyShortcuts(_ shortcut: ShortcutItem) {
        if !myShortcuts.contains(shortcut) { myShortcuts.append(shortcut) }
    }

    private func removeFromMyShortcuts(_ shortcut: ShortcutItem) {
        myShortcuts.removeAll { $0 == shortcut }
    }

    private func executeShortcut(_ shortcut: ShortcutItem) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        if let modifier = shortcut.modifier, !modifier.isEmpty {
            let mods = ModifierTranslator.translate(
                modifier.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) },
                for: targetOS
            )
            keyboardManager.handleKeyCombo(modifiers: mods, key: shortcut.keyCode)
            return
        }
        if shortcut.keyCode.contains("+") {
            let parts = shortcut.keyCode.components(separatedBy: "+")
            if parts.count >= 2, let key = parts.last {
                let translatedMods = ModifierTranslator.translate(Array(parts.dropLast()), for: targetOS)
                keyboardManager.handleKeyCombo(modifiers: translatedMods, key: key)
                return
            }
        }
        // Plain single key (no modifiers): send press then auto-release shortly after,
        // so the target never sees a stuck key. (Combos above self-release via handleKeyCombo.)
        keyboardManager.handleTapKey(shortcut.keyCode)
    }

    private func loadMyShortcuts() {
        guard let id = selectedProfileID else { myShortcuts = []; return }
        myShortcuts = profileManager.myShortcuts(for: id)
    }

    private func saveMyShortcuts() {
        guard let id = selectedProfileID else { return }
        profileManager.updateMyShortcuts(for: id, items: myShortcuts)
    }

    private func shareProfile(_ profile: ShortcutProfileData) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(profile.id).json")
        guard (try? data.write(to: tmp)) != nil else { return }
        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func handleProfileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        try? profileManager.addCustomProfile(from: data)
    }

    // MARK: - Info tab

    private var infoTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Shortcut Hub")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)

                Text("""
                Manage keyboard shortcut profiles:
                • Create or import profiles for different apps/games
                • Organize shortcuts into categories with colors/icons
                • Tap the star to add shortcuts to “My Shortcuts” (quick access)
                • Long‑press a shortcut to edit/delete (user profiles only)
                • Export profiles to share with friends
                • Use “My Shortcuts” button on the floating keyboard for instant access

                The hub shows built‑in profiles for popular software; you can
                override any shortcut or add your own.
                """)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            .padding(16)
        }
    }
}

#Preview {
    let kb = KeyboardInputManager(connectionManager: BluetoothConnectionManager())
    let coord = AppCoordinator()
    return ShortcutHubView(keyboardManager: kb, appCoordinator: coord)
}