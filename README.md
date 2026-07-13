# 3DGS Quick Look

English | [日本語](README-ja.md)

A macOS viewer for 3D Gaussian Splatting files:

- **.spz** — Quick Look preview with the spacebar in Finder
- **.ply (3DGS)** — standalone viewer window (double-click / Open With). The spacebar preview stays with Apple's Preview/Hydra system handler: registering the same UTI from a third-party Quick Look extension is not selected (verified on macOS 26.4; this priority is not documented in Apple's public APIs)

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

## ply2spz CLI

Convert 3DGS .ply (or .splat) to .spz — enables the spacebar preview and shrinks files ~10x:

```bash
ply2spz input.ply                    # writes input.spz next to it
ply2spz input.ply ~/Desktop/out.spz  # explicit output
ply2spz input.ply -f                 # overwrite existing output
```

Installed to your PATH by Homebrew (bundled inside the app at `Contents/Helpers/ply2spz`).

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
