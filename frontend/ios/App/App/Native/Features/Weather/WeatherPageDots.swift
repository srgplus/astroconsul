import SwiftUI
import UIKit

/// Page dots for the weather pager.
///
/// `UIPageControl` rather than a hand-rolled `HStack`: with thirty-odd
/// profiles a plain row of dots is wider than the screen and pushes the whole
/// bar sideways, while the system control compresses and windows the dots the
/// way Weather's does. It also takes a per-page image, which is how the
/// primary profile gets its house.
struct WeatherPageDots: UIViewRepresentable {

    let count: Int
    let index: Int
    let primaryIndex: Int?
    var onSelect: (Int) -> Void

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.currentPageIndicatorTintColor = .white
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.4)
        // No capsule of its own. `.prominent` draws one, but it is UIKit's
        // own light material and takes none of `weatherGlass`'s dark tint, so
        // next to the list button it read as a different surface entirely.
        // The bar wraps the control in the app's glass instead.
        control.backgroundStyle = .minimal
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.pageChanged(_:)),
            for: .valueChanged
        )
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.onSelect = onSelect

        if control.numberOfPages != count {
            control.numberOfPages = count
        }
        control.currentPage = index

        // A house, not the location arrow: the arrow is the hero's word for
        // "this reading came off a device fix", and the dot means something
        // else — the page that is *yours*, wherever it is being read from.
        let house = UIImage(systemName: "house.fill")
        for page in 0..<count {
            control.setIndicatorImage(page == primaryIndex ? house : nil, forPage: page)
        }
    }

    /// The most dots the capsule is ever as wide as. `UIPageControl` windows
    /// the dots itself once they stop fitting, but it centres what it draws in
    /// whatever width it is handed and leaves the rest of its bounds empty —
    /// which the glass capsule around it would then wrap, floating a bar-wide
    /// pill around a short row of dots. Capping the width at the window keeps
    /// the capsule on the dots at any profile count.
    ///
    /// Ten rather than the eleven a windowed control actually draws: it shrinks
    /// the outer dots as it windows, so eleven of them come to about what ten
    /// full-pitch ones measure.
    private static let maxVisibleDots = 10

    /// Sizes the control to its dots so the glass capsule hugs them. The
    /// metrics come from the control rather than from constants of ours:
    /// it reports no padding of its own, so one dot is the dot and each
    /// further dot is one pitch.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView control: UIPageControl,
        context: Context
    ) -> CGSize? {
        let single = control.size(forNumberOfPages: 1).width
        let pitch = control.size(forNumberOfPages: 2).width - single

        let intrinsic = single + pitch * CGFloat(max(count - 1, 0))
        let window = single + pitch * CGFloat(Self.maxVisibleDots - 1)

        var width = min(intrinsic, window)
        if let proposed = proposal.width, proposed.isFinite {
            width = min(width, proposed)
        }

        let height: CGFloat
        if let proposed = proposal.height, proposed.isFinite {
            height = proposed
        } else {
            height = control.size(forNumberOfPages: max(count, 1)).height
        }

        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func pageChanged(_ control: UIPageControl) {
            onSelect(control.currentPage)
        }
    }
}
