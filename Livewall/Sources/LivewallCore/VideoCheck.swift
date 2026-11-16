public struct VideoFacts: Equatable, Sendable {
    public var isPlayable: Bool
    public var hasVideoTrack: Bool
    public var width: Int
    public var height: Int
    public var badFrames: Int

    public init(isPlayable: Bool, hasVideoTrack: Bool, width: Int, height: Int, badFrames: Int) {
        self.isPlayable = isPlayable
        self.hasVideoTrack = hasVideoTrack
        self.width = width
        self.height = height
        self.badFrames = badFrames
    }
}

public enum VideoRejection: Error, Equatable, Sendable {
    case unsupportedFormat, noVideoTrack, corruptedFrames
}

public enum VideoWarning: Equatable, Sendable {
    case lowResolution
}

public enum VideoVerdict: Equatable, Sendable {
    case accepted(warning: VideoWarning?)
    case rejected(VideoRejection)
}

public enum VideoCheck {
    private static let hdShortSide = 720

    public static func evaluate(_ facts: VideoFacts) -> VideoVerdict {
        guard facts.isPlayable else { return .rejected(.unsupportedFormat) }
        guard facts.hasVideoTrack else { return .rejected(.noVideoTrack) }
        guard facts.badFrames == 0 else { return .rejected(.corruptedFrames) }
        let isLowResolution = min(facts.width, facts.height) < hdShortSide
        return .accepted(warning: isLowResolution ? .lowResolution : nil)
    }
}
