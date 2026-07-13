# 3DGS Quick Look

English | [日本語](README-ja.md)

A macOS viewer for 3D Gaussian Splatting files:

- **.spz** — Quick Look preview with the spacebar in Finder
- **.ply (3DGS)** — standalone viewer window (double-click / Open With). The spacebar preview for .ply cannot be overridden because Apple's built-in extension claims the type

Native implementation with Metal ([MetalSplatter](https://github.com/scier/MetalSplatter)) — no WebView, no auto-rotation.

- Drag to orbit, pinch or two-finger vertical scroll to zoom
- Shift+drag / right-drag (or two-finger horizontal scroll) to pan
- Toggle dark ⇄ light background, flip upside-down scenes (3DGS files have no standard up-axis) with the buttons in the top-right corner
- Broken files fall back to the standard Quick Look file info view

Requires macOS 15+ on Apple Silicon.

## Install (Homebrew)

```bash
brew install trapple/tap/3dgs-quicklook
open /Applications/SPZQuickLook.app   # first time only: registers the Quick Look extension
```

## Build from source

Requirements: Xcode / xcodegen (`brew install xcodegen`)

```bash
make install   # xcodegen → xcodebuild → copy to /Applications → register
```

If previews don't show up, try `make reset` (resets the qlmanage cache) and `killall Finder`.
Still nothing? Check the registration with `pluginkit -m | grep -i spz`.

## Development

```bash
make fixtures  # download sample .spz files (Niantic Labs samples) into fixtures/
make test      # unit tests
make ql        # open a preview directly via qlmanage -p fixtures/hornedlizard.spz
```

## License

[MIT](LICENSE)
