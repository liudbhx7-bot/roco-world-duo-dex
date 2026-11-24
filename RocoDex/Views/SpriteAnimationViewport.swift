import ImageIO
import SwiftUI

struct SpriteAnimationViewport: UIViewRepresentable {
    let url: URL
    let name: String
    let placeholder: UIImage
    let active: Bool
    let didFail: () -> Void

    func makeUIView(context: Context) -> SpriteAnimationView {
        let view = SpriteAnimationView()
        view.accessibilityLabel = name + "的动图"
        view.open(url, placeholder: placeholder, didFail: didFail)
        return view
    }

    func updateUIView(_ view: SpriteAnimationView, context: Context) {
        view.setActive(active)
    }

    static func dismantleUIView(_ view: SpriteAnimationView, coordinator: ()) {
        view.close()
    }
}

final class SpriteAnimationView: UIView {
    private struct Animation {
        let source: CGImageSource
        let first: CGImage
        let endTimes: [Double]

        init?(url: URL) {
            guard let input = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(input) > 1, let first = Self.decode(input, index: 0) else { return nil }
            source = input
            self.first = first
            var total = 0.0
            endTimes = (0..<CGImageSourceGetCount(input)).map { index in
                let props = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any]
                let png = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                let delay = png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double
                    ?? png?[kCGImagePropertyAPNGDelayTime] as? Double ?? 0.1
                total += delay > 0 ? delay : 0.01
                return total
            }
        }

        static func decode(_ source: CGImageSource, index: Int) -> CGImage? {
            CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false,
                                                            kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }

        func frame(at elapsed: CFTimeInterval) -> Int {
            var low = 0, high = endTimes.count
            while low < high {
                let mid = (low + high) / 2
                if endTimes[mid] <= elapsed { low = mid + 1 } else { high = mid }
            }
            return min(low, endTimes.count - 1)
        }
    }

    private let decodeQueue = DispatchQueue(label: "roco.animation.frame", qos: .userInitiated)
    private var animation: Animation?
    private var displayLink: CADisplayLink?
    private var previousTime: CFTimeInterval?
    private var elapsed: CFTimeInterval = 0
    private var currentFrame = 0
    private var pending = false
    private var active = false
    private var closed = false
    private var didFail: (() -> Void)?

    func open(_ url: URL, placeholder: UIImage, didFail: @escaping () -> Void) {
        self.didFail = didFail
        isOpaque = false
        layer.contentsGravity = .resizeAspect
        layer.contents = placeholder.cgImage
        decodeQueue.async { [weak self] in
            let animation = autoreleasepool { Animation(url: url) }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed else { return }
                guard let animation else { self.fail(); return }
                self.animation = animation
                self.present(animation.first, index: 0)
                self.accessibilityIdentifier = "animationViewport"
                self.accessibilityTraits = .image
                self.isAccessibilityElement = true
                let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
                self.displayLink = link
                link.isPaused = !self.active
                link.add(to: .main, forMode: .common)
            }
        }
    }

    override var accessibilityValue: String? {
        get {
            guard let animation else { return nil }
            return "第 \(currentFrame + 1) 帧，共 \(animation.endTimes.count) 帧"
        }
        set { super.accessibilityValue = newValue }
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        previousTime = nil
        displayLink?.isPaused = !value
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let animation, let duration = animation.endTimes.last else { return }
        if let previousTime { elapsed += max(0, link.timestamp - previousTime) }
        previousTime = link.timestamp
        elapsed.formTruncatingRemainder(dividingBy: duration)
        guard !pending else { return }
        let index = animation.frame(at: elapsed)
        guard index != currentFrame else { return }
        // Decode one frame at a time; a slow display refresh can skip ahead without queuing bitmaps.
        pending = true
        decodeQueue.async { [weak self] in
            let bitmap = autoreleasepool { Animation.decode(animation.source, index: index) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                guard self.active, !self.closed else { return }
                guard let bitmap else { self.fail(); return }
                self.present(bitmap, index: index)
            }
        }
    }

    private func present(_ bitmap: CGImage, index: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = bitmap
        CATransaction.commit()
        currentFrame = index
    }

    private func fail() {
        let notify = didFail
        close()
        notify?()
    }

    func close() {
        closed = true
        displayLink?.invalidate()
        displayLink = nil
        animation = nil
        didFail = nil
        layer.contents = nil
    }
}
