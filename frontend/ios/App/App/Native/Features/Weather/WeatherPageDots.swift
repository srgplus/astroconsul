import SwiftUI
import UIKit

/// Page dots for the weather pager.
///
/// `UIPageControl` rather than a hand-rolled `HStack`: with thirty-odd
/// profiles a plain row of dots is wider than the screen and pushes the whole
/// bar sideways, while the system control compresses and windows the dots the
/// way Weather's does. It also takes a per-page image, which is how the
/// primary profile gets Weather's location arrow.
struct WeatherPageDots: UIViewRepresentable {

    let count: Int
    let index: Int
    let primaryIndex: Int?
    var onSelect: (Int) -> Void

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.currentPageIndicatorTintColor = .white
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.4)
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

        let arrow = UIImage(systemName: "location.fill")
        for page in 0..<count {
            control.setIndicatorImage(page == primaryIndex ? arrow : nil, forPage: page)
        }
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
