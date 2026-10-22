-- diagrams.lua: render ```mermaid and ```wavedrom fenced blocks into figures.
--
-- Source syntax is plain markdown so WYSIWYG editors render it:
--
--   ```mermaid
--   graph TD; A-->B
--   ```
--
--   Figure: Register bank hierarchy.
--
--   ```wavedrom
--   {"file": "wavedrom/chip.json", "key": "pb_read_1to1"}
--   ```
--
--   Figure: Peripheral bus read.
--
-- A paragraph starting with "Figure:" directly after a diagram fence or an image becomes
-- the figure caption (numbered Figure X-Y). Without one, a diagram is placed inline and
-- unnumbered, and an image keeps its alt text as the caption (pandoc's implicit figure).
-- A wavedrom fence holding {"file": ...} (optionally "key" for a JSON file with several
-- named diagrams) reads the diagram from that file in the document directory.
-- Pandoc attributes still work too: {.mermaid caption="..." width=80% file=... key=...}.
--
-- Rendered files are cached in $DOCGEN_OUT/diagrams by content hash, so unchanged
-- diagrams are not re-rendered. mermaid -> PDF via mmdc (Chromium print, vector);
-- wavedrom -> SVG via wavedrom-cli, then PDF via rsvg-convert.

local out_dir = os.getenv("DOCGEN_OUT") or "out"
local mmdc = os.getenv("DOCGEN_MMDC") or "mmdc"
local wavedrom = os.getenv("DOCGEN_WAVEDROM") or "wavedrom-cli"
local rsvg = os.getenv("DOCGEN_RSVG_CONVERT") or "rsvg-convert"
local puppeteer_cfg = os.getenv("DOCGEN_PUPPETEER_CONFIG")
local mmdc_pdf_flags = os.getenv("DOCGEN_MMDC_PDF_FLAGS") or ""
local diag_dir = out_dir .. "/diagrams"

-- Diagram text font, from metadata: `mainfont` (the PDF body font) and `diagram-font-size`
-- (default 11pt). Mermaid gets them through a generated config file; WaveDrom's SVG has
-- Helvetica 11pt hard-coded in its style block and is rewritten before conversion.
local font_family = nil
local font_size_pt = 11

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then error("docgen: cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("a")
  f:close()
  return s
end

local function write_file(path, s)
  local f, err = io.open(path, "w")
  if not f then error("docgen: cannot write " .. path .. ": " .. tostring(err)) end
  f:write(s)
  f:close()
end

local function split_flags(s)
  local t = {}
  for w in s:gmatch("%S+") do t[#t + 1] = w end
  return t
end

local function run(cmd, args)
  local ok, err = pcall(pandoc.pipe, cmd, args, "")
  if not ok then
    error(string.format("docgen: %s %s failed:\n%s", cmd, table.concat(args, " "), tostring(err)))
  end
end

-- Resolve the diagram source text: fence body, or file= (with optional key=).
local function source_text(kind, block)
  local file = block.attributes["file"]
  local key = block.attributes["key"]
  if not file and kind == "wavedrom" and block.text:match("^%s*{") then
    -- {"file": "...", "key": "..."} in the fence body is a reference, not a diagram
    local ok, obj = pcall(pandoc.json.decode, block.text, false)
    if ok and type(obj) == "table" and obj.file then
      file = obj.file
      key = obj.key
    end
  end
  if not file then
    if block.text:match("^%s*$") then
      error("docgen: empty " .. kind .. " block (no diagram source and no file reference)")
    end
    return block.text
  end
  local text = read_file(file)
  if key then
    if kind ~= "wavedrom" then error("docgen: key= is only supported for wavedrom blocks") end
    local obj = pandoc.json.decode(text, false)
    if type(obj) ~= "table" or obj[key] == nil then
      error("docgen: key '" .. key .. "' not found in " .. file)
    end
    return pandoc.json.encode(obj[key])
  end
  return text
end

local function mermaid_config()
  local cfg = string.format('{"themeVariables": {"fontFamily": %s, "fontSize": "%dpx"}}',
    font_family and ('"' .. font_family .. ', sans-serif"') or '"sans-serif"',
    math.floor(font_size_pt * 96 / 72 + 0.5))
  return cfg
end

-- Point WaveDrom's SVG style block at the document font and scale its font sizes
-- (11pt base) to diagram-font-size.
local function restyle_wavedrom(svg_path)
  local svg = read_file(svg_path)
  if font_family then
    svg = svg:gsub("font%-family:[^;}\"]+", "font-family:" .. font_family)
  end
  local scale = font_size_pt / 11
  if math.abs(scale - 1) > 0.001 then
    svg = svg:gsub("font%-size:(%d+%.?%d*)pt", function(n)
      return string.format("font-size:%.1fpt", tonumber(n) * scale)
    end)
  end
  write_file(svg_path, svg)
end

local function render(kind, src)
  pandoc.system.make_directory(diag_dir, true)
  -- the font settings are part of the cache key
  local key = src .. "\n%font:" .. tostring(font_family) .. ":" .. font_size_pt
  local base = diag_dir .. "/" .. kind .. "-" .. pandoc.utils.sha1(key):sub(1, 12)
  local pdf = base .. ".pdf"
  if file_exists(pdf) then return pdf end

  if kind == "mermaid" then
    local srcfile = base .. ".mmd"
    write_file(srcfile, src)
    local cfgfile = diag_dir .. "/mermaid-config.json"
    write_file(cfgfile, mermaid_config())
    local args = { "-i", srcfile, "-o", pdf, "-c", cfgfile }
    for _, flag in ipairs(split_flags(mmdc_pdf_flags)) do args[#args + 1] = flag end
    if puppeteer_cfg and puppeteer_cfg ~= "" then
      args[#args + 1] = "-p"
      args[#args + 1] = puppeteer_cfg
    end
    run(mmdc, args)
  else
    local srcfile = base .. ".json"
    local svg = base .. ".svg"
    write_file(srcfile, src)
    run(wavedrom, { "-i", srcfile, "-s", svg })
    restyle_wavedrom(svg)
    run(rsvg, { "-f", "pdf", "-o", pdf, svg })
  end
  if not file_exists(pdf) then
    error("docgen: " .. kind .. " renderer produced no output at " .. pdf)
  end
  return pdf
end

local function caption_inlines(text)
  local doc = pandoc.read(text, "markdown")
  local first = doc.blocks[1]
  if first and (first.t == "Para" or first.t == "Plain") then return first.content end
  return pandoc.Inlines({ pandoc.Str(text) })
end

local function diagram_kind(block)
  if block.t ~= "CodeBlock" then return nil end
  if block.classes:includes("mermaid") then return "mermaid" end
  if block.classes:includes("wavedrom") then return "wavedrom" end
  return nil
end

-- Registry of keyed tables and figures: key -> "Table" | "Figure". Filled while the
-- block lists are processed, then used by the Pandoc handler to rewrite [Table](#key)
-- and [Figure](#key) links into "Table 1-1" style references.
local refs = {}

-- Parse a caption paragraph of the form "<word>: text" or "<word> key: text".
-- Returns key (or nil) and the caption inlines, or nil if the paragraph is not one.
local function keyed_caption(block, word)
  if not block or block.t ~= "Para" then return nil end
  local c = block.content
  local first = c[1]
  if not (first and first.t == "Str") then return nil end
  local key, rest_from
  if first.text == word .. ":" then
    rest_from = 2
  elseif first.text == word and c[2] and c[2].t == "Space" and c[3] and c[3].t == "Str" then
    key = c[3].text:match("^([%w_%-]+):$")
    if not key then return nil end
    rest_from = 4
  else
    return nil
  end
  local inlines = pandoc.Inlines({})
  for k = rest_from, #c do inlines:insert(c[k]) end
  while inlines[1] and inlines[1].t == "Space" do inlines:remove(1) end
  return key, inlines
end

local function register(key, kind)
  if not key then return end
  if refs[key] and refs[key] ~= kind then
    error(string.format("docgen: caption key '%s' used for both a %s and a %s", key, refs[key], kind))
  end
  refs[key] = kind
end

local function make_figure(image, caption, attr)
  return pandoc.Figure({ pandoc.Plain({ image }) },
                       pandoc.Caption({ pandoc.Plain(caption) }),
                       attr or pandoc.Attr())
end

local function diagram_image(kind, block)
  local pdf = render(kind, source_text(kind, block))
  local img_attr = pandoc.Attr("", {}, {})
  for _, k in ipairs({ "width", "height" }) do
    if block.attributes[k] then img_attr.attributes[k] = block.attributes[k] end
  end
  return pandoc.Image({}, pdf, "", img_attr)
end

-- The single image inside a Figure or an image-only paragraph, or nil.
local function lone_image(block)
  if block.t == "Para" and #block.content == 1 and block.content[1].t == "Image" then
    return block.content[1]
  end
  if block.t == "Figure" then
    local img
    pandoc.walk_block(block, { Image = function(im) if not img then img = im end end })
    return img
  end
  return nil
end

local function Blocks(blocks)
  local out = pandoc.Blocks({})
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    local step = 1
    local kind = diagram_kind(b)
    local fig_key, fig_caption = keyed_caption(blocks[i + 1], "Figure")
    if kind then
      local caption = fig_caption
      if caption then
        step = 2
      elseif b.attributes["caption"] then
        caption = caption_inlines(b.attributes["caption"])
      end
      local image = diagram_image(kind, b)
      if caption then
        local id = fig_key or b.identifier
        register(fig_key, "Figure")
        out:insert(make_figure(image, caption, pandoc.Attr(id, {}, {})))
      else
        out:insert(pandoc.Para({ image }))
      end
    elseif fig_caption and lone_image(b) then
      local attr = b.t == "Figure" and b.attr or pandoc.Attr()
      if fig_key then attr.identifier = fig_key end
      register(fig_key, "Figure")
      out:insert(make_figure(lone_image(b), fig_caption, attr))
      step = 2
    elseif b.t == "Table" then
      local tbl_key, tbl_caption = keyed_caption(blocks[i + 1], "Table")
      if tbl_caption then
        b.caption = pandoc.Caption({ pandoc.Plain(tbl_caption) })
        if tbl_key then b.attr.identifier = tbl_key end
        register(tbl_key, "Table")
        step = 2
      end
      out:insert(b)
    else
      out:insert(b)
    end
    i = i + step
  end
  return out
end

-- Rewrite [Table](#key) / [Figure](#key) links to "Table~\ref{key}" so the text always
-- carries the current number; the whole "Table 1-1" is the link, not just the number.
-- Runs after every block list has been processed.
local function PandocDoc(doc)
  if not FORMAT:match("latex") then return nil end
  local heading_ids = {}
  doc:walk({ Header = function(h) if h.identifier ~= "" then heading_ids[h.identifier] = true end end })
  return doc:walk({
    Link = function(link)
      local key = link.target:match("^#(.+)$")
      if not key then return nil end
      local kind = refs[key]
      if kind then
        return pandoc.RawInline("latex", "\\hyperref[" .. key .. "]{" .. kind .. "~\\ref*{" .. key .. "}}")
      end
      if not heading_ids[key] then
        io.stderr:write("docgen: link target #" .. key .. " matches no heading, table or figure key\n")
      end
      return nil
    end,
  })
end

local function Meta(meta)
  if meta.mainfont then font_family = pandoc.utils.stringify(meta.mainfont) end
  if meta["diagram-font-size"] then
    local s = pandoc.utils.stringify(meta["diagram-font-size"])
    local n = tonumber(s:match("^([%d%.]+)%s*pt$") or "")
    if not n then error("docgen: diagram-font-size must be a point size like 11pt, got '" .. s .. "'") end
    font_size_pt = n
  end
end

return {
  { Meta = Meta },
  { Blocks = Blocks, Pandoc = PandocDoc },
}
