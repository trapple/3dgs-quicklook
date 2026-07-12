# 3DGS Quick Look

English | [日本語](README-ja.md)

A macOS Quick Look extension that previews .spz (3D Gaussian Splatting) files with the spacebar in Finder.
Native implementation with Metal ([MetalSplatter](https://github.com/scier/MetalSplatter)) — no WebView, no auto-rotation.

- Drag to orbit, pinch or two-finger vertical scroll to zoom
- Shift+drag / right-drag (or two-finger horizontal scroll) to pan
- Toggle dark ⇄ light background with the button in the top-right corner
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
