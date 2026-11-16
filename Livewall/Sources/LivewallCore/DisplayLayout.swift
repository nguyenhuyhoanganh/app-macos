import CoreGraphics

public enum DisplayLayout {
    /// Scales AppKit screen frames into a top-left-origin box, centred and proportional.
    public static func fit(_ frames: [String: CGRect], in size: CGSize) -> [String: CGRect] {
        guard let bounds = frames.values.reduce(nil, { (partial: CGRect?, frame) in
            partial?.union(frame) ?? frame
        }), bounds.width > 0, bounds.height > 0 else { return [:] }

        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let xInset = (size.width - bounds.width * scale) / 2
        let yInset = (size.height - bounds.height * scale) / 2

        return frames.mapValues { frame in
            CGRect(
                x: xInset + (frame.minX - bounds.minX) * scale,
                y: yInset + (bounds.maxY - frame.maxY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
        }
    }
}
