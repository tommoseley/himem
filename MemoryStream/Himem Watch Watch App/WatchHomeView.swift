import SwiftUI

/// Watch · Pages (swipe model). Three pages around capture-as-center,
/// in the spirit of Apple's Workout app: each page is *adjacent context*
/// for the same continuous activity, not navigation through the app.
///
/// Pages, left → right:
///   1. **LATEST** — replay the most recent memory (read-only).
///   2. **CAPTURE** — the job. Watch lands here on wrist-raise / app open.
///   3. **PENDING** — queue + sync status, earned when clips wait for phone.
///
/// Recording state: the route switches to `.recording` (handled by
/// `WatchRootView`), which replaces the TabView entirely. Page dots
/// vanish because the TabView isn't mounted — the user can't accidentally
/// swipe off a recording in progress. Stop & save or ✕ are the only exits.
///
/// The old "Pending · N · Tap to view" footer is retired: the page dots
/// imply Pending exists, and a deliberate swipe is the explicit
/// affordance.
struct WatchHomeView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    @ObservedObject var pending: WatchPendingManifest

    /// Identifies the three pages. Conformance to `Hashable` is what
    /// `TabView.selection` needs.
    enum Page: Hashable {
        case latest
        case capture
        case pending
    }

    /// Watch always lands on Capture on wrist-raise / app launch.
    @State private var selection: Page = .capture

    var body: some View {
        // Header is OUTSIDE the TabView so it renders at a single,
        // fixed Y on every page. Putting it inside each page (whether
        // via VStack child or `safeAreaInset`) puts it at the top of
        // *that page's slot* — and `.tabViewStyle(.page)` doesn't
        // guarantee identical slot tops across pages because each page's
        // vertical centering depends on its own content height. One
        // header above the TabView, title driven by `selection`, is the
        // only way to get all three pages aligned.
        //
        // The outer VStack ignores the top container safe area so the
        // `HIMEM · <PAGE>` header sits in the watchOS status-bar band
        // alongside the system clock — that's where the design (Image
        // 21) places it. The TabView below stays within the normal
        // content area; only the header strip extends upward.
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                WatchPageHeader(pageTitle: title(for: selection))

                TabView(selection: $selection) {
                    WatchLatestPage()
                        .tag(Page.latest)

                    WatchCapturePage(onTap: {
                        coordinator.route = .recording
                    })
                    .tag(Page.capture)

                    WatchPendingListView(pending: pending, embedded: true)
                        .tag(Page.pending)
                }
                .tabViewStyle(.page)
            }

            // Discard toast — overlaid on home for 0.5s after the user
            // hits the corner ✕ on the recording screen. Pairs with the
            // existing `.click` haptic on the discard path.
            if coordinator.showDiscardedToast {
                Text("Discarded")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.top, 32)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: coordinator.showDiscardedToast)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func title(for page: Page) -> String {
        switch page {
        case .latest: return "LATEST"
        case .capture: return "RECORD"
        case .pending: return "PENDING"
        }
    }
}

/// Shared header used at the top of every swipe page. Format:
/// `HIMEM · <PAGE>` — left-aligned, small caps, muted white.
///
/// Use via the `.watchPageHeader(_:)` view modifier so the header is
/// pinned to the top via `safeAreaInset`. Inserting it as a VStack
/// child instead would let the TabView's vertical centering drag it
/// down with the content on pages whose body doesn't fill the screen
/// (Latest and Pending have small content and would otherwise center).
struct WatchPageHeader: View {
    let pageTitle: String

    var body: some View {
        HStack(spacing: 6) {
            Text("HIMEM")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.55))
            Text("·")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
            Text(pageTitle)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 17)
        // Top inset chosen so HIMEM's baseline lines up with the bottom
        // of the system clock in the watchOS status-bar band. Since the
        // outer VStack ignores the top container safe area, this padding
        // is the only thing positioning the header.
        .padding(.top, 24)
    }
}

extension View {
    /// Pins a `WatchPageHeader` to the top of the page via
    /// `safeAreaInset`. The pinned header doesn't participate in the
    /// page's vertical centering, so all three swipe pages land their
    /// `HIMEM · <PAGE>` chrome at the same Y-coordinate regardless of
    /// content size.
    func watchPageHeader(_ title: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            WatchPageHeader(pageTitle: title)
        }
    }
}

/// Center page: the mic and a single-line label. Tapping the mic enters
/// the recording route (handled by `WatchRootView`). Sized so the mic
/// dominates and the dots have breathing room below.
private struct WatchCapturePage: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(WatchTheme.accent.opacity(0.10))
                        .frame(width: 122, height: 122)
                    Circle()
                        .fill(WatchTheme.accent)
                        .frame(width: 92, height: 92)
                        .shadow(color: WatchTheme.accent.opacity(0.45), radius: 12, x: 0, y: 4)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            .accessibilityHint("Tap to start a voice recording.")

            Text("Tap to record")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))

            Spacer(minLength: 0)
        }
        // Extra bottom padding so the content lifts off the page-dot
        // indicator strip rendered by `.tabViewStyle(.page)`.
        .padding(.bottom, 22)
    }
}
