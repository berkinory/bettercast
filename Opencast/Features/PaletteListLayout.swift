import SwiftUI

struct PaletteListLayout<Content: View, Target: Hashable>: View {
    let scroll: ListScrollIntent
    let scrollTarget: Target?
    let content: Content

    init(
        scroll: ListScrollIntent,
        scrollTarget: Target? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scroll = scroll
        self.scrollTarget = scrollTarget
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                guard scroll.kind == .follow, let scrollTarget else { return }
                proxy.scrollTo(scrollTarget)
            }
        }
    }
}
