//
//  MacroPanelView.swift
//  Openterface_iOS
//

import SwiftUI

struct MacroPanelView: View {
    @ObservedObject var macroManager: MacroInputManager
    @State private var editingMacro: Macro?
    @State private var isCreating = false
    @State private var showVerifiedOnly = false
    @State private var filterSystem: MacroTargetSystem?

    var defaultFilter: MacroTargetSystem? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header filters
                filterBar

                if filteredMacros.isEmpty {
                    emptyState
                } else {
                    macroGrid
                }
            }
            .navigationTitle("Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                MacroEditorView(macroManager: macroManager, globalTargetOS: defaultFilter)
            }
            .sheet(item: $editingMacro) { macro in
                MacroEditorView(macroManager: macroManager, editingMacro: macro)
            }
        }
        .onAppear {
            if let defaultFilter {
                filterSystem = defaultFilter
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Verified filter
                Button {
                    withAnimation { showVerifiedOnly.toggle() }
                } label: {
                    Label(
                        showVerifiedOnly ? "Verified" : "All",
                        systemImage: showVerifiedOnly ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundColor(showVerifiedOnly ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // OS filter
                ForEach(MacroTargetSystem.allCases) { system in
                    Button {
                        withAnimation {
                            filterSystem = filterSystem == system ? nil : system
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: system.sfSymbol)
                                .font(.caption2)
                            Text(system.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(filterSystem == system ? .accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Grid

    private var macroGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 90), spacing: 8)
            ], spacing: 12) {
                ForEach(filteredMacros) { macro in
                    MacroGridButton(
                        macro: macro,
                        onRun: { macroManager.execute(macro) },
                        onEdit: { editingMacro = macro },
                        onDelete: { macroManager.delete(id: macro.id) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No macros yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Tap + to create your first macro")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private var filteredMacros: [Macro] {
        var result = macroManager.macros
        if showVerifiedOnly {
            result = result.filter { $0.isVerified }
        }
        if let filterSystem {
            result = result.filter { $0.targetSystem == filterSystem }
        }
        return result
    }
}

// MARK: - Grid Button

struct MacroGridButton: View {
    let macro: Macro
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onRun) {
            VStack(spacing: 4) {
                if macro.isVerified {
                    Text("Verified")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Image(systemName: macro.icon)
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(height: 30)
                Text(macro.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .contextMenu {
            Button(action: onRun) {
                Label("Run", systemImage: "play.fill")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(macro.label)
        .accessibilityHint(macro.description.isEmpty ? "Run macro" : macro.description)
    }
}

#Preview {
    // Preview with a mock — won't fully work without a real keyboard manager
    // but shows the layout
    Text("MacroPanelView requires KeyboardInputManager")
}
