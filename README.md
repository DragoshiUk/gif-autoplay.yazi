# gif-autoplay.yazi

A [yazi](https://yazi-rs.github.io/) plugin that auto-plays animated GIFs in
the preview pane, using kitty's terminal-driven graphics protocol animation.

## The problem

yazi's built-in image previewer — and `ya.image_show` in general — only ever
transmits a single static frame of any image. GIFs included. Hover a GIF in
yazi today and you get frame one, forever.

## How it works

- Kitty's graphics protocol supports *terminal-driven* animation: once you
  transmit an image's frames plus a loop count, the terminal itself owns all
  future redraws. The client that sent the frames doesn't need to stay
  running — which is exactly why `kitty +kitten icat some.gif` on its own
  already animates, with zero polling.
- This plugin's `peek()` hands the hovered GIF to `icat` once:
  ```
  kitty +kitten icat --unicode-placeholder --place=<rect> --loop=-1 <file>
  ```
  Kitty then loops the animation forever, entirely on its own.
- **Cleanup on navigate-away.** yazi's kitty driver
  ([`yazi-adapter/src/drivers/kgp.rs`](https://github.com/sxyazi/yazi/blob/main/yazi-adapter/src/drivers/kgp.rs))
  keeps track of a single "currently shown" rect and erases it — via a
  global "delete all images" escape — *before* drawing the next preview.
  But it only knows to do that for images shown through `ya.image_show`.
  Since the actual animated draw bypasses that call (we shell out to `icat`
  directly), yazi never learns anything is on screen there, and that
  erase-before-draw never fires once you move to the next file — the
  animated GIF just keeps looping, ghosted behind whatever you preview
  next. The fix: `peek()` calls `ya.image_show()` once first. This paints
  an instant static first frame (immediately covered by the animated one,
  so it's not something you actually see) purely to register that
  bookkeeping. Whatever you look at next then cleans up correctly, through
  yazi's own normal path.
- **Pixel-perfect alignment.** yazi's own static preview doesn't use kitty's
  *classic* image placement protocol — it uses the Unicode Placeholder
  method (virtual placement via specially-encoded characters written into
  the terminal's text grid, see `Kgp::place`), which always *stretches* the
  image to exactly fill the given cell rectangle, no leftover margin.
  `icat`'s default placement mode does its own, independent
  aspect-fit-with-letterboxing computation instead — and since it has no
  vertical-alignment flag, it appears to top-anchor, so any shortfall in
  its fit shows up as a sliver of the (covered-over) static frame peeking
  out along the *bottom* of non-square GIFs specifically. No amount of
  padding the placement box fixes that, since it's two genuinely different
  display mechanisms disagreeing, not a rounding error. Passing
  `--unicode-placeholder` to `icat` makes it use the exact same
  stretch-to-fill mechanism yazi itself uses, so both draws agree
  pixel-for-pixel.

The whole thing is one file, under 90 lines — worth just reading if you're
curious, it's not much bigger than this README.

## Requirements

- yazi, with a kitty-graphics-protocol-capable terminal
- [kitty](https://sw.kovidgoyal.net/kitty/) terminal specifically — this
  plugin shells out to `kitty +kitten icat`, and relies on kitty's Unicode
  Placeholder support (`graphics_unicode_placeholders`)
- `kitty` must be on `PATH`

On any other terminal/adaptor (or if `kitty` isn't found), it falls back to
yazi's normal static preview — same as if the plugin weren't installed.

## Installation

Via yazi's plugin manager:

```sh
ya pkg add DragoshiUk/gif-autoplay
```

Or manually:

```sh
git clone https://github.com/DragoshiUk/gif-autoplay.yazi ~/.config/yazi/plugins/gif-autoplay.yazi
```

## Configuration

Add a previewer rule to `~/.config/yazi/yazi.toml`, **ahead of** any general
`image/*` rule — yazi matches previewer rules top to bottom and uses the
first match, so the more specific `image/gif` rule needs to come first:

```toml
[plugin]
prepend_previewers = [
    { mime = "image/gif", run = "gif-autoplay" },
    { mime = "image/*", run = "image" }, # yazi's built-in, or your own previewer
]
```

That's it — no further options.

## Limitations

- **kitty-only.** Terminals using sixel, iTerm2's protocol, or ueberzugpp
  fall back to yazi's default static-first-frame behavior, since this
  plugin only speaks kitty's graphics protocol extensions directly.
- Kitty drives the animation independently once frames are transmitted, so
  a GIF's own embedded loop-count metadata isn't read or respected — this
  plugin always requests infinite looping (`--loop=-1`).
- No play/pause controls. It's always-on autoplay for as long as the GIF is
  the hovered/previewed file.
- Every `peek()` re-spawns `icat` (an external process). It's fast in
  practice, but scrubbing very quickly through a directory full of large
  GIFs will spawn a process per hover.

## Why not decode frames and loop in Lua?

An earlier design decoded GIF frames with `ffmpeg`/`imagemagick` and looped
`ya.image_show()` calls with `ya.sleep()` between them, entirely from Lua.
It was dropped in favor of the current approach for two reasons:

1. yazi's plugin API doesn't document what happens to a long-running,
   sleeping `peek()` coroutine when you navigate to another file — there's
   no documented cancellation hook, so a naive loop risked leaking a
   background coroutine or fighting the next file's own preview for screen
   real estate.
2. It's strictly worse animation than what the terminal already offers for
   free: each `ya.image_show()` call is a full independent still-image
   transmission, so per-frame timing is at the mercy of Lua's scheduler and
   process-launch jitter, not the smooth, terminal-owned redraw loop kitty
   already implements natively for exactly this purpose.

## License

MIT — see [LICENSE](LICENSE).
