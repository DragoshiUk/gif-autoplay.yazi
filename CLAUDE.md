# CLAUDE.md

Context for working on this repo. User-facing docs are in `README.md` — keep
debugging/rationale detail out of there (see the "Why not…" section for the
tone) and in code comments instead.

## What it is

A single-file yazi plugin: hovering an animated GIF hands it to
`kitty +kitten icat` once, and kitty's graphics protocol animates it
terminal-side with no process left running. `main.lua` is ~85 lines and is
the whole thing (no `package.toml` — installed by clone / `ya pkg`).

## Where it lives

Repo is `~/Projects/gif-autoplay.yazi`, symlinked to
`~/.config/yazi/plugins/gif-autoplay.yazi` — edits here are live in yazi on
the next hover (it re-reads plugin files per invocation). Public repo
`DragoshiUk/gif-autoplay.yazi`.

## Load-bearing details — don't "simplify" these

- **The `ya.image_show()` call before `icat`** is not redundant. yazi's
  kitty driver only erases the previous preview if it was shown through
  `ya.image_show`; the `icat` overlay bypasses that, so without the
  throwaway call first, the GIF keeps looping ghosted behind whatever you
  view next. It paints an instant static first frame that the animation
  immediately covers.
- **`--unicode-placeholder` on `icat`** must stay. yazi places images with
  the Unicode Placeholder method (stretch-to-fill); `icat`'s default
  classic placement does aspect-fit-with-margin and top-anchors, showing a
  sliver of the covered static frame along the bottom of non-square GIFs.
  The flag makes `icat` use the same stretch-to-fill yazi uses.
- **`--loop=-1` always.** The GIF's own loop-count metadata is not read;
  animation is infinite by design.

## Rejected approach (don't reintroduce)

Decoding frames with ffmpeg/imagemagick and looping `ya.image_show()` +
`ya.sleep()` from Lua. Dropped: no documented cancellation hook for a
sleeping `peek()` coroutine on navigate-away, and per-frame timing is worse
than the terminal's native redraw loop. See README.

## Testing

Manual only — no harness. In kitty: hover a GIF (should animate), navigate
away (should stop and not ghost), hover a non-GIF image (unaffected,
yazi's normal preview). On a non-kitty terminal it must fall back silently.

## Requirements

yazi + kitty (on `PATH`), kitty terminal specifically. `--- @since` at the
top of `main.lua` pins the yazi plugin API version.
