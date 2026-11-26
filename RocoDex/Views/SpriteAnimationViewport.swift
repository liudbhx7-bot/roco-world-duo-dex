import ImageIO
import SwiftUI

struct SpriteAnimationViewport: UIViewRepresentable {
    let animation: SpiritAnimation
    let playback: PortraitPlayback
    let name: String
    let placeholder: UIImage
    let active: Bool

    func makeUIView(context: Context) -> SpriteAnimationView {
        let view = SpriteAnimationView()
        view.accessibilityLabel = name + "的动图"
        view.open(animation, playback: playback, placeholder: placeholder)
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
    private final class Animation {
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
    private let artworkLayer = CALayer()
    private var framing = AnimationFraming.fullCanvas
    private var canvasSize = CGSize.zero
    private var viewport = AnimationFraming.fullCanvas.viewport(for: 0, isEntry: false)
    private var clip: Animation?
    private var idle: Animation?
    private var isEntry = false
    private var openJob: DispatchWorkItem?
    private var playback: PortraitPlayback?
    private var displayLink: CADisplayLink?
    private var previousTime: CFTimeInterval?
    private var elapsed: CFTimeInterval = 0
    private var currentFrame = 0
    private var pending = false
    private var active = false
    private var closed = false

    func open(_ motion: SpiritAnimation, playback: PortraitPlayback, placeholder: UIImage) {
        self.playback = playback
        isOpaque = false
        clipsToBounds = true
        layer.addSublayer(artworkLayer)
        if let bitmap = placeholder.cgImage { present(bitmap, index: 0) }
        let entryURL = playback.didStartEntry ? nil : motion.entry
        let job = DispatchWorkItem { [weak self] in
            let entry = entryURL.flatMap { url in autoreleasepool { Animation(url: url) } }
            // Warm the idle clip and its first bitmap before running the entry clock.
            let idle = motion.idle.flatMap { url in autoreleasepool { Animation(url: url) } }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed else { return }
                guard let first = entry ?? idle else {
                    if playback.didStartEntry && motion.idle == nil { self.finishEntry() }
                    else { self.fail() }
                    return
                }
                self.idle = idle
                self.clip = first
                self.isEntry = entry != nil
                self.framing = motion.framing.validated(entryFrameCount: entry?.endTimes.count, idleFrameCount: idle?.endTimes.count)
                if self.isEntry { playback.didStartEntry = true }
                self.present(first.first, index: 0)
                self.accessibilityIdentifier = "animationViewport"
                self.accessibilityTraits = .image
                self.isAccessibilityElement = true
                let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
                self.displayLink = link
                link.isPaused = !self.active
                link.add(to: .main, forMode: .common)
            }
        }
        openJob = job
        decodeQueue.async(execute: job)
    }

    override var accessibilityValue: String? {
        get {
            guard let clip else { return nil }
            return "\(isEntry ? "出场" : "待机")，第 \(currentFrame + 1) 帧，共 \(clip.endTimes.count) 帧"
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
        guard let clip, let duration = clip.endTimes.last else { return }
        if let previousTime { elapsed += max(0, link.timestamp - previousTime) }
        previousTime = link.timestamp

        if isEntry && elapsed >= duration {
            guard let idle else { finishEntry(); return }
            self.clip = idle
            isEntry = false
            elapsed = 0
            present(idle.first, index: 0)
            return
        }
        if !isEntry { elapsed.formTruncatingRemainder(dividingBy: duration) }
        guard !pending else { return }
        let index = clip.frame(at: elapsed)
        guard index != currentFrame else { return }
        // Keep at most one in-flight bitmap; a late entry frame cannot overwrite the idle clip.
        pending = true
        decodeQueue.async { [weak self] in
            let bitmap = autoreleasepool { Animation.decode(clip.source, index: index) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                guard self.active, !self.closed, self.clip === clip else { return }
                guard let bitmap else { self.fail(); return }
                self.present(bitmap, index: index)
            }
        }
    }

    private func present(_ bitmap: CGImage, index: Int) {
        canvasSize = CGSize(width: bitmap.width, height: bitmap.height)
        viewport = framing.viewport(for: index, isEntry: isEntry)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.frame = AnimationFraming.imageFrame(canvas: canvasSize, viewport: viewport, in: bounds)
        artworkLayer.contents = bitmap
        CATransaction.commit()
        currentFrame = index
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.frame = AnimationFraming.imageFrame(canvas: canvasSize, viewport: viewport, in: bounds)
        CATransaction.commit()
    }

    private func finishEntry() {
        playback?.animationPreference = false
        close()
    }

    private func fail() {
        playback?.failed = true
        close()
    }

    func close() {
        closed = true
        openJob?.cancel()
        openJob = nil
        displayLink?.invalidate()
        displayLink = nil
        clip = nil
        idle = nil
        playback = nil
        // Keep the displayed frame until SwiftUI removes the view.
    }
}
