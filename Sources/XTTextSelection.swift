import AppKit
import VisionKit

/// 将系统图片文字选择能力提供给 Objective-C 贴图窗口。
@MainActor
@objc(XTTextSelectionController)
public final class XTTextSelectionController: NSObject, ImageAnalysisOverlayViewDelegate {
    private enum State: Equatable {
        case idle, recognizing, ready, noText, failed, unavailable
    }

    private let analyzer = ImageAnalyzer()
    private let analysisOverlay = ImageAnalysisOverlayView(frame: .zero)
    private var analysisTask: Task<Void, Never>?
    private var generation = 0
    private var state: State = .idle

    @objc public weak var contentView: NSView?
    @objc public var onStateChange: (() -> Void)?
    @objc public var contextMenuProvider: (() -> NSMenu)?
    @objc public private(set) var recognizedText = ""
    @objc public var overlayView: NSView { analysisOverlay }
    @objc public var selectedText: String { analysisOverlay.selectedText }
    @objc public var hasText: Bool { !recognizedText.isEmpty }
    @objc public var hasSelection: Bool { analysisOverlay.hasActiveTextSelection }
    @objc public var recognizing: Bool { state == .recognizing }
    @objc public var supported: Bool { ImageAnalyzer.isSupported }

    @objc public var statusMessage: String {
        switch state {
        case .idle: return "提取图片文字"
        case .recognizing: return "正在识别文字…"
        case .ready: return "可直接选字 · ⌘C 复制"
        case .noText: return "未识别到文字，可点击重试"
        case .failed: return "文字识别失败，可点击重试"
        case .unavailable: return "当前设备不支持文字识别"
        }
    }

    public override init() {
        super.init()
        analysisOverlay.delegate = self
        analysisOverlay.preferredInteractionTypes = .textSelection
        // 应用使用自己的工具栏和右键菜单。
        analysisOverlay.isSupplementaryInterfaceHidden = true
        analysisOverlay.autoresizingMask = [.width, .height]
    }

    @objc(recognizeImage:)
    public func recognizeImage(_ image: NSImage) {
        analysisTask?.cancel()
        generation += 1
        let requestGeneration = generation
        analysisOverlay.resetSelection()
        analysisOverlay.analysis = nil
        recognizedText = ""

        guard ImageAnalyzer.isSupported else {
            changeState(.unavailable)
            return
        }
        // 在主线程固定不可变位图，避免将可变 NSImage 跨线程交给识别器。
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            changeState(.failed)
            return
        }

        changeState(.recognizing)
        var configuration = ImageAnalyzer.Configuration(.text)
        // 中英文优先，只使用当前系统声明支持的识别语言。
        configuration.locales = ImageAnalyzer.supportedTextRecognitionLanguages.filter {
            $0.hasPrefix("zh") || $0.hasPrefix("en")
        }
        let analyzer = analyzer
        analysisTask = Task { [weak self] in
            do {
                let analysis = try await analyzer.analyze(cgImage, orientation: .up, configuration: configuration)
                guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
                self.analysisOverlay.analysis = analysis
                self.analysisOverlay.setContentsRectNeedsUpdate()
                self.recognizedText = analysis.transcript
                self.analysisTask = nil
                self.changeState(self.hasText ? .ready : .noText)
            } catch {
                guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
                self.analysisTask = nil
                self.changeState(.failed)
            }
        }
    }

    @objc(hasTextAtPoint:)
    public func hasText(at point: NSPoint) -> Bool {
        hasText && analysisOverlay.analysisHasText(at: point)
    }

    @objc public func selectAllText() {
        let text = analysisOverlay.text
        guard hasText, !text.isEmpty else { return }
        analysisOverlay.window?.makeFirstResponder(analysisOverlay)
        analysisOverlay.selectedRanges = [text.startIndex..<text.endIndex]
    }

    @objc public func clearSelection() {
        analysisOverlay.resetSelection()
    }

    @objc public func updateLayout() {
        analysisOverlay.setContentsRectNeedsUpdate()
    }

    @objc public func invalidate() {
        generation += 1
        analysisTask?.cancel()
        analysisTask = nil
        analysisOverlay.resetSelection()
        analysisOverlay.analysis = nil
        analysisOverlay.delegate = nil
        recognizedText = ""
        contentView = nil
        onStateChange = nil
        contextMenuProvider = nil
    }

    deinit {
        analysisTask?.cancel()
    }

    private func changeState(_ state: State) {
        self.state = state
        onStateChange?()
    }

    public func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        // 贴图始终将原图铺满整个视图，使用系统要求的单位坐标。
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    public func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
        contentView
    }

    public func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu,
                            for event: NSEvent, at point: CGPoint) -> NSMenu {
        contextMenuProvider?() ?? menu
    }
}
