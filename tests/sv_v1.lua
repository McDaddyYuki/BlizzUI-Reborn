BlizzUIRebornDB = { version = 1, editor = { grid = true, spacing = 80, snap = true, advanced = true, previews = { cast = false } },
  layouts = { Shared = { status = true, compartment = true, frames = { target = { x = .66, y = .32, scale = 120 } } } } }
BlizzUIRebornCharDB = { version = 1, active = { scope = "character", name = "My Layout" },
  layouts = { ["My Layout"] = { status = true, compartment = false, frames = {
     player = { x = .34, y = .32, scale = 100 },
     action1 = { x = .5, y = .07, orientation = "horizontal", rows = 1, icons = 12, scale = 90, padding = 2, always = false, hideArt = true, hideScrolling = true },
     status = { side = "right", size = 28, spacing = 32, offsetX = 0, offsetY = 0 },
     debuffs = { x = .5, y = .5 } } } } }
do local f = PlayerFrame; f.__userPlaced = true; f.__movable = true end
