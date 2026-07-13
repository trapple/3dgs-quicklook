import AppKit
import MetalKit

/// マウス入力をオービットカメラに変換する MTKView。
/// 背景色は SplatRenderer の clear が透明 (0,0,0,0) なのを利用し、layer の背景色で切り替える
final class SplatMetalView: MTKView {
    private let sceneRenderer: SplatSceneRenderer

    var isDarkBackground = true {
        didSet { applyBackgroundColor() }
    }

    /// true ならスクロール/ピンチを view 自身で処理する (単体ビューア用)。
    /// QL 拡張ではホスト window のイベントモニタ経由で zoom/pan が呼ばれるため false のまま
    var handlesScrollEventsDirectly = false

    init(device: MTLDevice, sceneRenderer: SplatSceneRenderer) {
        self.sceneRenderer = sceneRenderer
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm_srgb
        depthStencilPixelFormat = .depth32Float
        sampleCount = 1
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        delegate = sceneRenderer
        wantsLayer = true
        layer?.isOpaque = false
        // 常時描画ループを止め、入力・ソート完了時のみ再描画する (CPU/GPU 負荷対策)
        isPaused = true
        enableSetNeedsDisplay = true
        sceneRenderer.redrawTarget = self
        applyBackgroundColor()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // spec: ダーク #262626 ⇄ ライト #d9d9d9
    private func applyBackgroundColor() {
        layer?.backgroundColor = isDarkBackground
            ? CGColor(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)
            : CGColor(red: 0xd9 / 255.0, green: 0xd9 / 255.0, blue: 0xd9 / 255.0, alpha: 1)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // ドラッグは NSPanGestureRecognizer で受ける (ifc-quicklook で確立した最終解)。理由:
    // - QL のリモートビュー転送 (ViewBridge) は生の mouseDown/mouseDragged を表示面ごとに
    //   違う形で殺す: スペースキーパネルでは NSEvent の deltaX/deltaY が 0 に潰され、
    //   Finder プレビュー欄ではホスト側機構に消費されて override まで届かない。
    // - レコグナイザはホストとのイベント調停に乗るため両面で機能し、translation(in:) は
    //   デルタ潰しの影響も受けない (Apple 純正 usdz プレビューと同方式)。
    private var gesturesInstalled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !gesturesInstalled, window != nil else { return }
        gesturesInstalled = true
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        // 注意: 右/中ボタンを buttonMask 指定のレコグナイザで受ける構成は QL パネルでは
        // 一切発火しない (実測)。右(中)ドラッグは生イベント + 位置差分で処理する (下記)
    }

    /// 差分を取り出してリセット (AppKit 座標は Y 上向き → 下向き正へ反転)
    private func consumeTranslation(_ g: NSPanGestureRecognizer) -> (CGFloat, CGFloat) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        return (t.x, -t.y)
    }

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        let (dx, dy) = consumeTranslation(g)
        if NSEvent.modifierFlags.contains(.shift) {
            pan(deltaX: dx, deltaY: dy)
        } else {
            sceneRenderer.camera.rotate(
                deltaYaw: Float(dx) * 0.01,
                deltaPitch: Float(dy) * 0.01
            )
            needsDisplay = true
        }
    }

    // 右 (2 本指クリック) / 中ボタンドラッグのパン。
    // レコグナイザ (buttonMask) は QL パネルで発火しないため生イベントで受ける。
    // 生イベントの右/中ボタン系はパネルでもビューまで届く (左と違いホストに食われない) が、
    // deltaX/deltaY は例によって 0 に潰されるため locationInWindow の位置差分で計算する。
    // Finder プレビュー欄では右イベント自体が届かないため、欄でのパンは Shift+ドラッグを使う
    private var lastPanDragLocation: NSPoint?

    private func panByLocationDelta(_ event: NSEvent) {
        let loc = event.locationInWindow
        if let last = lastPanDragLocation {
            // AppKit 座標は Y 上向き → 下向き正へ反転
            pan(deltaX: loc.x - last.x, deltaY: last.y - loc.y)
        }
        lastPanDragLocation = loc
    }

    override func rightMouseDown(with event: NSEvent) {
        lastPanDragLocation = event.locationInWindow
    }
    override func rightMouseDragged(with event: NSEvent) {
        panByLocationDelta(event)
    }
    override func rightMouseUp(with event: NSEvent) {
        lastPanDragLocation = nil
    }
    override func otherMouseDown(with event: NSEvent) {
        lastPanDragLocation = event.locationInWindow
    }
    override func otherMouseDragged(with event: NSEvent) {
        panByLocationDelta(event)
    }
    override func otherMouseUp(with event: NSEvent) {
        lastPanDragLocation = nil
    }

    func zoom(magnificationDelta: CGFloat) {
        sceneRenderer.camera.zoom(factor: Float(1.0 + magnificationDelta))
        needsDisplay = true
    }

    func pan(deltaX: CGFloat, deltaY: CGFloat) {
        sceneRenderer.camera.pan(deltaX: Float(deltaX), deltaY: Float(deltaY))
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard handlesScrollEventsDirectly else {
            super.scrollWheel(with: event)
            return
        }
        // 支配軸で判定: 縦スクロール = ズーム、横スクロール = パン
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            pan(deltaX: event.scrollingDeltaX, deltaY: 0)
        } else {
            zoom(magnificationDelta: event.scrollingDeltaY * 0.01)
        }
    }

    override func magnify(with event: NSEvent) {
        guard handlesScrollEventsDirectly else {
            super.magnify(with: event)
            return
        }
        zoom(magnificationDelta: event.magnification)
    }

    // MARK: - オーバーレイ (背景切替 + 上下反転ボタン + 省略警告)

    func installBackgroundToggle() {
        let backgroundButton = overlayButton(
            symbolName: "circle.lefthalf.filled", help: "背景色を切り替え",
            action: #selector(toggleBackground(_:))
        )
        let flipButton = overlayButton(
            symbolName: "arrow.up.arrow.down", help: "上下を反転",
            action: #selector(toggleFlip(_:))
        )
        NSLayoutConstraint.activate([
            backgroundButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            backgroundButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            flipButton.topAnchor.constraint(equalTo: backgroundButton.bottomAnchor, constant: 10),
            flipButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    private func overlayButton(symbolName: String, help: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: help)!,
            target: self, action: action
        )
        button.isBordered = false
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        return button
    }

    @objc private func toggleBackground(_ sender: NSButton) {
        isDarkBackground.toggle()
    }

    @objc private func toggleFlip(_ sender: NSButton) {
        sceneRenderer.camera.toggleFlip()
        needsDisplay = true
    }

    /// 上限超過はサイレントに切り捨てず必ず可視化する (spec)
    func showTruncationWarning(count: Int) {
        let label = NSTextField(labelWithString: "⚠︎ \(count.formatted()) 個のスプラットを省略")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
        ])
    }
}
