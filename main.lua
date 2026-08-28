--- @since 26.1.22
-- Auto-plays animated GIFs in the preview pane.
--
-- yazi's built-in image previewer (and ya.image_show in general) only ever
-- transmits a single static frame, so GIFs never animate. Kitty's graphics
-- protocol supports terminal-driven animation though: once frames + a loop
-- count are transmitted, the terminal itself owns the redraw loop and the
-- sending process can exit immediately. So this shells out once to
-- `kitty +kitten icat` and lets kitty do the animating.
--
-- Cleanup on navigate-away: yazi's kitty driver (yazi-adapter/src/drivers/
-- kgp.rs) tracks one "currently shown" rect (Adapter.shown) and, on every
-- ya.image_show call, erases whatever was shown there *first* -- including
-- a global "delete all images" escape -- before drawing the new thing. Our
-- icat call bypasses that pipeline entirely, so yazi never learns an image
-- is on screen there, and that erase-before-draw never fires once you move
-- to the next file. Fix: call ya.image_show once ourselves before the icat
-- overlay, purely to register that bookkeeping (it also happens to paint
-- an instant static first frame). Whatever the next file's own previewer
-- does then cleans up correctly, animation included.
--
-- Alignment: yazi's own static frame (yazi-adapter/src/drivers/kgp.rs)
-- doesn't use icat's default "classic" placement protocol at all -- it
-- uses the Unicode Placeholder method (virtual placement via diacritic-
-- encoded characters written into the grid, see Kgp::place), which always
-- *stretches* the image to exactly fill whatever cell grid it's given.
-- icat's default --place mode is the classic placement protocol, which
-- does its own independent aspect-fit-with-margin computation and, having
-- no vertical-align flag, appears to top-anchor -- so any shortfall in its
-- fit shows up as a gap at the bottom specifically. No amount of padding
-- the box fixes that, since it's a different display mechanism, not a
-- rounding error. Passing --unicode-placeholder makes icat use the same
-- stretch-to-fill mechanism yazi itself uses, so both draws exactly fill
-- the same cell rect with no fit-margin to disagree about.
--
-- Only works when the frontend is kitty (or another terminal implementing
-- the kitty graphics protocol's animation extension and its Unicode
-- Placeholder / "graphics_unicode_placeholders" support). Falls back to a
-- normal static preview otherwise.

local M = {}

local function show_static(job)
	local cache = ya.file_cache(job)
	if not cache or not fs.cha(cache) then
		cache = job.file.url
	end
	return ya.image_show(cache, job.area)
end

function M:peek(job)
	if not job.area or job.area.w == 0 or job.area.h == 0 then
		local _, err = show_static(job)
		return ya.preview_widget(job, err)
	end

	local area, err = show_static(job)
	if not area then
		ya.err("gif-autoplay", "image_show failed", err)
		return ya.preview_widget(job, err)
	end

	local place = ("%dx%d@%dx%d"):format(area.w, area.h, area.x, area.y)
	local status, icat_err = Command("kitty")
		:arg { "+kitten", "icat" }
		:arg { "--transfer-mode", "stream" }
		:arg { "--stdin", "no" }
		:arg { "--unicode-placeholder" }
		:arg { "--place", place }
		:arg { "--loop", "-1" }
		:arg { tostring(job.file.url) }
		:stdout(Command.INHERIT)
		:stderr(Command.PIPED)
		:status()

	if not status or not status.success then
		return ya.err("gif-autoplay", "icat failed", icat_err or (status and status.code))
	end

	ya.preview_widget(job, nil)
end

function M:seek() end

return M
