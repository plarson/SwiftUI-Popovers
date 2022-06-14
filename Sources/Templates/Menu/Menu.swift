//
//  Menu.swift
//  Popovers
//
//  Created by A. Zheng (github.com/aheze) on 2/3/22.
//  Copyright © 2022 A. Zheng. All rights reserved.
//

import SwiftUI

public extension Templates {
    /// A set of attributes for the popover menu.
    struct MenuConfiguration {
        public var holdDelay = CGFloat(0.2) /// The duration of a long press to activate the menu.
        public var presentationAnimation = Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 1)
        public var dismissalAnimation = Animation.spring(response: 0.4, dampingFraction: 0.9, blendDuration: 1)
        public var labelFadeAnimation = Animation.default /// The animation used when calling the `fadeLabel`.
        public var clipContent = true /// Replicate the system's default clipping animation.
        public var sourceFrameInset = UIEdgeInsets(top: -8, left: -8, bottom: -8, right: -8)
        public var originAnchor = Popover.Attributes.Position.Anchor.bottom /// The label's anchor.
        public var popoverAnchor = Popover.Attributes.Position.Anchor.top /// The menu's anchor.
        public var scaleAnchor: Popover.Attributes.Position.Anchor? /// If nil, the anchor will be automatically picked.
        public var excludedFrames: (() -> [CGRect]) = { [] }
        public var menuBlur = UIBlurEffect.Style.prominent
        public var width: CGFloat? = CGFloat(240) /// If nil, hug the content.
        public var cornerRadius = CGFloat(14)
        public var shadow = Shadow.system
        public var backgroundColor = Color.clear /// A color that is overlaid over the entire screen, just underneath the menu.
        public var scaleRange = CGFloat(40) ... CGFloat(90) /// For rubber banding - the range at which rubber banding should be applied.
        public var minimumScale = CGFloat(0.7) /// For rubber banding - the scale the the popover should shrink to when rubber banding.

        /// Create the default attributes for the popover menu.
        public init(
            holdDelay: CGFloat = CGFloat(0.2),
            presentationAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 1),
            dismissalAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.9, blendDuration: 1),
            labelFadeAnimation: Animation = .easeOut,
            sourceFrameInset: UIEdgeInsets = .init(top: -8, left: -8, bottom: -8, right: -8),
            originAnchor: Popover.Attributes.Position.Anchor = .bottom,
            popoverAnchor: Popover.Attributes.Position.Anchor = .top,
            scaleAnchor: Popover.Attributes.Position.Anchor? = nil,
            excludedFrames: @escaping (() -> [CGRect]) = { [] },
            menuBlur: UIBlurEffect.Style = .prominent,
            width: CGFloat? = CGFloat(240),
            cornerRadius: CGFloat = CGFloat(14),
            shadow: Shadow = .system,
            backgroundColor: Color = .clear,
            scaleRange: ClosedRange<CGFloat> = 30 ... 80,
            minimumScale: CGFloat = 0.85
        ) {
            self.holdDelay = holdDelay
            self.presentationAnimation = presentationAnimation
            self.dismissalAnimation = dismissalAnimation
            self.labelFadeAnimation = labelFadeAnimation
            self.sourceFrameInset = sourceFrameInset
            self.originAnchor = originAnchor
            self.popoverAnchor = popoverAnchor
            self.scaleAnchor = scaleAnchor
            self.excludedFrames = excludedFrames
            self.menuBlur = menuBlur
            self.width = width
            self.cornerRadius = cornerRadius
            self.shadow = shadow
            self.backgroundColor = backgroundColor
            self.scaleRange = scaleRange
            self.minimumScale = minimumScale
        }
    }

    /// The popover that gets presented.
    internal struct MenuView<Content: View>: View {
        @ObservedObject var model: MenuModel
        let present: (Bool) -> Void
        let configuration: MenuConfiguration

        /// The menu buttons.
        var content: Content

        /// For the scale animation.
        @State var expanded = false

        init(
            model: MenuModel,
            present: @escaping (Bool) -> Void,
            configuration: MenuConfiguration,
            @ViewBuilder content: () -> Content
        ) {
            self.model = model
            self.present = present
            self.configuration = configuration
            self.content = content()
        }

        var body: some View {
            PopoverReader { context in
                content

                    /// Inject model.
                    .environmentObject(model)

                    /// Work with frames.
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .frame(width: configuration.width)
                    .fixedSize() /// Hug the width of the inner content.
                    .modifier(ClippedBackgroundModifier(context: context, configuration: configuration, expanded: expanded)) /// Clip the content if desired.
                    .scaleEffect(expanded ? 1 : 0.2, anchor: configuration.scaleAnchor?.unitPoint ?? model.getScaleAnchor(from: context))
                    .scaleEffect(model.scale, anchor: configuration.scaleAnchor?.unitPoint ?? model.getScaleAnchor(from: context))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                model.hoveringItemID = model.getItemID(from: value.location)

                                /// Rubber-band the menu.
                                withAnimation {
                                    if let distance = model.getDistanceFromMenu(from: value.location) {
                                        if configuration.scaleRange.contains(distance) {
                                            let percentage = (distance - configuration.scaleRange.lowerBound) / (configuration.scaleRange.upperBound - configuration.scaleRange.lowerBound)
                                            let scale = 1 - (1 - configuration.minimumScale) * percentage
                                            model.scale = scale
                                        } else if distance < configuration.scaleRange.lowerBound {
                                            model.scale = 1
                                        } else {
                                            model.scale = configuration.minimumScale
                                        }
                                    }
                                }
                            }
                            .onEnded { value in
                                withAnimation {
                                    model.scale = 1
                                }

                                let activeIndex = model.getItemID(from: value.location)
                                model.selectedItemID = activeIndex
                                model.hoveringItemID = nil
                                if activeIndex != nil {
                                    present(false)
                                }
                            }
                    )
                    .onAppear {
                        withAnimation(configuration.presentationAnimation) {
                            expanded = true
                        }
                        /// When the popover is about to be dismissed, shrink it again.
                        context.attributes.onDismiss = {
                            withAnimation(configuration.dismissalAnimation) {
                                expanded = false
                            }

                            /// Clear frames once the menu is done presenting.
                            model.frames = []
                        }
                        context.attributes.onContextChange = { context in
                            model.menuFrame = context.frame
                        }
                    }
            }
        }
    }

    /// A special button for use inside `PopoverMenu`s.
    struct MenuItem<Content: View>: View {
        @State var itemID = UUID()
        @EnvironmentObject var model: MenuModel

        public let action: () -> Void
        public let label: (Bool) -> Content

        public init(
            _ action: @escaping (() -> Void),
            label: @escaping (Bool) -> Content
        ) {
            self.action = action
            self.label = label
        }

        public var body: some View {
            label(model.hoveringItemID == itemID)

                /// Read the frame of the menu item.
                .frameReader { frame in

                    /// Don't set frames when dismissing.
                    guard model.present else { return }
                    let itemFrame = MenuItemFrame(itemID: itemID, frame: frame)

                    /// If there's already a frame with the same ID, change it.
                    let existingFrameIndex = model.frames.firstIndex { $0.itemID == itemID }
                    if let existingFrameIndex = existingFrameIndex {
                        model.frames[existingFrameIndex].frame = frame
                    } else {
                        /// Newest, most up-to-date frames are at the end.
                        model.frames.append(itemFrame)
                    }
                }
                .onValueChange(of: model.selectedItemID) { _, newValue in
                    if newValue == itemID {
                        action()
                    }
                }
        }
    }

    /// A wrapper for `PopoverMenuItem` that mimics the system menu button style.
    struct MenuButton: View {
        public let text: Text?
        public let image: Image?
        public let action: () -> Void

        /// A wrapper for `PopoverMenuItem` that mimics the system menu button style (title + image)
        public init(
            title: String? = nil,
            systemImage: String? = nil,
            _ action: @escaping (() -> Void)
        ) {
            if let title = title {
                text = Text(title)
            } else {
                text = nil
            }

            if let systemImage = systemImage {
                image = Image(systemName: systemImage)
            } else {
                image = nil
            }

            self.action = action
        }

        /// A wrapper for `PopoverMenuItem` that mimics the system menu button style (title + image).
        public init(
            text: Text? = nil,
            image: Image? = nil,
            _ action: @escaping (() -> Void)
        ) {
            self.text = text
            self.image = image
            self.action = action
        }

        public var body: some View {
            MenuItem(action) { pressed in
                HStack {
                    if let text = text {
                        text
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let image = image {
                        image
                    }
                }
                .accessibilityElement(children: .combine) /// Merge text and image into a single element.
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                .background(pressed ? Templates.buttonHighlightColor : Color.clear) /// Add highlight effect when pressed.
            }
        }
    }

    /// Place this inside a Menu to separate content.
    struct MenuDivider: View {
        /// Place this inside a Menu to separate content.
        public init() {}
        public var body: some View {
            Rectangle()
                .fill(Color(UIColor.label))
                .opacity(0.15)
                .frame(height: 7)
        }
    }

    /// Replicates the system menu's subtle clip effect.
    internal struct ClippedBackgroundModifier: ViewModifier {
        let context: Popover.Context
        let configuration: MenuConfiguration
        let expanded: Bool
        func body(content: Content) -> some View {
            if configuration.clipContent {
                content

                    /// Replicates the system menu's subtle clip effect.
                    .mask(
                        Color.clear
                            .overlay(
                                RoundedRectangle(cornerRadius: configuration.cornerRadius)
                                    .frame(height: expanded ? nil : context.frame.height / 3),
                                alignment: .top
                            )
                    )

                    /// Avoid limiting the frame of the content to ensure proper hit-testing (for popover dismissal).
                    .background(
                        Templates.VisualEffectView(configuration.menuBlur)
                            .cornerRadius(configuration.cornerRadius)
                            .popoverShadow(shadow: configuration.shadow)
                            .frame(height: expanded ? nil : context.frame.height / 3),
                        alignment: .top
                    )
            } else {
                content
            }
        }
    }
}