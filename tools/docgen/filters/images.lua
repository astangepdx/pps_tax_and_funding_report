-- images.lua: prepare images for the xelatex run that docgen.mk drives itself.
--
-- pandoc only resolves --resource-path and converts SVG when it runs LaTeX itself; docgen
-- writes the .tex and runs xelatex separately (to iterate until longtable widths settle),
-- so this filter does both: an image path that does not exist as written is looked up in
-- img/, and SVG images are converted to PDF with rsvg-convert into $DOCGEN_OUT/images.

if not FORMAT:match("latex") then return {} end

local out_dir = os.getenv("DOCGEN_OUT") or "out"
local rsvg = os.getenv("DOCGEN_RSVG_CONVERT") or "rsvg-convert"

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function Image(img)
  local src = img.src
  if src:match("^%a+://") then return nil end
  if not exists(src) and exists("img/" .. src) then src = "img/" .. src end
  if not exists(src) then
    error("docgen: image not found: " .. img.src .. " (looked in the document directory and img/)")
  end
  if src:lower():match("%.svg$") then
    local dir = out_dir .. "/images"
    pandoc.system.make_directory(dir, true)
    local f = io.open(src, "rb"); local data = f:read("a"); f:close()
    local pdf = dir .. "/" .. pandoc.utils.sha1(data):sub(1, 12) .. ".pdf"
    if not exists(pdf) then
      local ok, err = pcall(pandoc.pipe, rsvg, { "-f", "pdf", "-o", pdf, src }, "")
      if not ok then error("docgen: rsvg-convert failed on " .. src .. ":\n" .. tostring(err)) end
    end
    src = pdf
  end
  img.src = src
  return img
end
