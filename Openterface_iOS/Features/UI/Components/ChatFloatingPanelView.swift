//
//  ChatFloatingPanelView.swift
//  Openterface_iOS
//

import SwiftUI

struct ChatFloatingPanelView: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var authService: GitHubAuthService
    @ObservedObject var appCoordinator: AppCoordinator
    @Binding var showLoginSheet: Bool
    @Binding var isPresented: Bool

    @State private var panelOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let panelSize = panelSize(in: geometry.size)
            let liveOffset = clampedOffset(
                baseOffset: panelOffset,
                dragOffset: dragOffset,
                containerSize: geometry.size,
                panelSize: panelSize
            )

            ZStack(alignment: .top) {
                ChatView(
                    chatManager: chatManager,
                    authService: authService,
                    appCoordinator: appCoordinator,
                    showLoginSheet: $showLoginSheet,
                    onDone: {
                        isPresented = false
                    }
                )

                // Keep drag interaction limited to a small centered grab handle.
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 44, height: 6)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                        .highPriorityGesture(dragGesture(containerSize: geometry.size, panelSize: panelSize))
                    Spacer()
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
            .offset(liveOffset)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func panelSize(in containerSize: CGSize) -> CGSize {
        let width = min(max(containerSize.width * 0.48, 340), 560)
        let height = min(max(containerSize.height * 0.7, 420), 760)
        return CGSize(width: width, height: height)
    }

    private func clampedOffset(
        baseOffset: CGSize,
        dragOffset: CGSize,
        containerSize: CGSize,
        panelSize: CGSize
    ) -> CGSize {
        let proposedOffset = CGSize(
            width: baseOffset.width + dragOffset.width,
            height: baseOffset.height + dragOffset.height
        )

        let horizontalLimit = max((containerSize.width - panelSize.width) / 2, 0)
        let verticalLimit = max((containerSize.height - panelSize.height) / 2, 0)

        return CGSize(
            width: min(max(proposedOffset.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposedOffset.height, -verticalLimit), verticalLimit)
        )
    }

    private func dragGesture(containerSize: CGSize, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if dragOffset == .zero {
                    Logger.shared.debug(
                        "Chat drag began (global) startOffset=(\(format(panelOffset.width)), \(format(panelOffset.height))) start=(\(format(value.startLocation.x)), \(format(value.startLocation.y))) container=\(Int(containerSize.width))x\(Int(containerSize.height)) panel=\(Int(panelSize.width))x\(Int(panelSize.height))",
                        category: .ui
                    )
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let finalOffset = clampedOffset(
                    baseOffset: panelOffset,
                    dragOffset: value.translation,
                    containerSize: containerSize,
                    panelSize: panelSize
                )

                Logger.shared.debug(
                    "Chat drag ended translation=(\(format(value.translation.width)), \(format(value.translation.height))) finalOffset=(\(format(finalOffset.width)), \(format(finalOffset.height)))",
                    category: .ui
                )

                panelOffset = finalOffset
                dragOffset = .zero
            }
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
