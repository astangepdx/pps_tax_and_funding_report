-- tables.lua: typeset every table as a full grid (all cell borders) in LaTeX output.
--
-- Each Table is rebuilt as a longtable with vertical rules between and around the
-- columns and a horizontal rule under every row. Everything else follows pandoc's own
-- table writer: column alignments, column widths (from the separator-row dashes once a
-- table line exceeds 72 characters, otherwise content-sized), the caption and \label set
-- by diagrams.lua, and a header repeated on every page the table spans.
-- Must run after diagrams.lua, which attaches keyed captions and identifiers.
-- Merged cells (row/column spans) are not supported yet and stop the build.

if not FORMAT:match("latex") then return {} end

-- Set from metadata `table-header-color` (a hex RGB value); the template defines the
-- matching xcolor named docgentableheader.
local header_color = false
-- Measuring copies of each table, keyed by the number in the "%docgen-table:N" first line of
-- the emitted longtable; KeepTogether places them (see below).
local measures = {}
local table_count = 0
local captioned_tables = 0
-- Gap between the header-row fill and every rule around it (see row_latex).
local HEADER_BACKOFF = "0.3pt"

local function latex_of(blocks)
  local s = pandoc.write(pandoc.Pandoc(blocks), "latex")
  return (s:gsub("%s+$", ""))
end

local function cell_latex(cell, in_p_column)
  local s = latex_of(cell.contents)
  if not in_p_column then
    -- l/c/r columns cannot hold paragraph breaks
    s = s:gsub("\n%s*\n", " ")
    -- soul's \hl infinite-loops in l/c/r cells on TeX Live >= 2025; box instead
    s = s:gsub("\\hl{", "\\docgencellhl{")
  end
  return s
end

local align_letter = {
  AlignLeft = "l", AlignRight = "r", AlignCenter = "c", AlignDefault = "l",
}
local align_ragged = {
  AlignLeft = "\\raggedright", AlignRight = "\\raggedleft",
  AlignCenter = "\\centering", AlignDefault = "\\raggedright",
}

local function colspec_latex(colspecs)
  local n = #colspecs
  local has_widths = false
  for _, cs in ipairs(colspecs) do
    if type(cs[2]) == "number" and cs[2] > 0 then has_widths = true end
  end
  local parts = {}
  for _, cs in ipairs(colspecs) do
    local align = tostring(cs[1])
    if has_widths then
      local w = type(cs[2]) == "number" and cs[2] or (1 / n)
      -- \hfuzz: a p-cell paragraph is measured against the column's text area, which
      -- excludes the \tabcolsep padding, so an unbreakable word can overflow by up to
      -- \tabcolsep before it reaches the vertical rule. Only report overflow beyond
      -- that. It has to be set here, inside the cell, because array's p-cell setup runs
      -- \sloppy, which resets \hfuzz to 0.5pt.
      parts[#parts + 1] = string.format(
        ">{%s\\arraybackslash\\hfuzz=\\tabcolsep}p{(\\linewidth - %d\\tabcolsep - %d\\arrayrulewidth) * \\real{%.4f}}",
        align_ragged[align] or "\\raggedright", 2 * n, n + 1, w)
    else
      parts[#parts + 1] = align_letter[align] or "l"
    end
  end
  return "|" .. table.concat(parts, "|") .. "|", has_widths
end

local function row_latex(row, has_widths, is_header)
  local cells = {}
  for _, cell in ipairs(row.cells) do
    if (cell.row_span or 1) > 1 or (cell.col_span or 1) > 1 then
      error("docgen: merged table cells (row/column spans) are not supported yet")
    end
    cells[#cells + 1] = cell_latex(cell, has_widths)
  end
  -- The header fill backs off HEADER_BACKOFF from every rule around it: the \rowcolor
  -- overhang stops it short of the vertical rules (the default \tabcolsep butts it against
  -- them) and a thin \noalign skip separates it from the horizontal rules. Otherwise viewers
  -- snapping the fill to screen pixels paint over the thin rules at normal zoom.
  if is_header and header_color then
    local oh = "[\\dimexpr\\tabcolsep-" .. HEADER_BACKOFF .. "\\relax]"
    return "\\rowcolor{docgentableheader}" .. oh .. oh .. " " .. table.concat(cells, " & ")
      .. " \\\\ \\noalign{\\vskip " .. HEADER_BACKOFF .. "}\\hline"
  end
  return table.concat(cells, " & ") .. " \\\\ \\hline"
end

local function Table(tbl)
  local spec, has_widths = colspec_latex(tbl.colspecs)

  local head = {}
  for _, row in ipairs(tbl.head.rows) do head[#head + 1] = row_latex(row, has_widths, true) end
  local body = {}
  for _, b in ipairs(tbl.bodies) do
    for _, row in ipairs(b.head) do body[#body + 1] = row_latex(row, has_widths) end
    for _, row in ipairs(b.body) do body[#body + 1] = row_latex(row, has_widths) end
  end
  for _, row in ipairs(tbl.foot.rows) do body[#body + 1] = row_latex(row, has_widths) end

  local caption_inlines = pandoc.utils.blocks_to_inlines(tbl.caption.long or {})
  local has_caption = #caption_inlines > 0
  if has_caption then captioned_tables = captioned_tables + 1 end
  local label = tbl.identifier ~= "" and ("\\label{" .. tbl.identifier .. "}") or ""

  -- Measuring copy for \docgenkeeptable (template): caption plus the same rows in a
  -- tabular, so LaTeX can start a new page first when the table fits on one page.
  local measure = { "\\begin{minipage}{\\linewidth}\\centering" }
  if has_caption then
    measure[#measure + 1] = "{\\bfseries " .. latex_of({ pandoc.Plain(caption_inlines) }) .. "}\\par\\vspace{6pt}"
  end
  measure[#measure + 1] = "\\begin{tabular}{" .. spec .. "}"
  measure[#measure + 1] = #head > 0 and ((header_color and ("\\hline\\noalign{\\vskip " .. HEADER_BACKOFF .. "}") or "\\hline")) or "\\hline"
  for _, r in ipairs(head) do measure[#measure + 1] = r end
  for _, r in ipairs(body) do measure[#measure + 1] = r end
  measure[#measure + 1] = "\\end{tabular}"
  measure[#measure + 1] = "\\end{minipage}"

  table_count = table_count + 1
  measures[table_count] = table.concat(measure, "\n")
  local out = { "%docgen-table:" .. table_count }
  if not has_caption then out[#out + 1] = "{\\def\\LTcaptype{none} % do not increment counter" end
  out[#out + 1] = "\\begin{longtable}[]{" .. spec .. "}"
  local top_rule = header_color and ("\\hline\\noalign{\\vskip " .. HEADER_BACKOFF .. "}") or "\\hline"
  local head_block = top_rule .. "\n" .. table.concat(head, "\n")
  if has_caption then
    out[#out + 1] = "\\caption{" .. latex_of({ pandoc.Plain(caption_inlines) }) .. "}" .. label .. "\\tabularnewline"
    if #head > 0 then
      out[#out + 1] = head_block
      out[#out + 1] = "\\endfirsthead"
      out[#out + 1] = head_block
      out[#out + 1] = "\\endhead"
    else
      out[#out + 1] = "\\hline"
    end
  elseif #head > 0 then
    out[#out + 1] = head_block
    out[#out + 1] = "\\endhead"
  else
    out[#out + 1] = "\\hline"
  end
  for _, r in ipairs(body) do out[#out + 1] = r end
  out[#out + 1] = "\\end{longtable}"
  if not has_caption then out[#out + 1] = "}" end
  return pandoc.RawBlock("latex", table.concat(out, "\n"))
end

-- Put each table's \docgenkeeptable check (template) in front of the table, or in front
-- of the heading directly above it, so a page break never strands a heading. Body text
-- above a table is never moved with it. Figures get the same treatment, but only when a
-- heading sits directly above them (a figure alone already moves as a unit).
local function table_number(block)
  if block and block.t == "RawBlock" and block.format == "latex" then
    return tonumber(block.text:match("^%%docgen%-table:(%d+)"))
  end
end

-- Measuring copy of a Figure: its image, bounded exactly as the template bounds it,
-- plus the caption.
local function figure_measure(fig)
  local img
  pandoc.walk_block(fig, { Image = function(im) if not img then img = im end end })
  if not img then return nil end
  local caption = pandoc.utils.blocks_to_inlines(fig.caption.long or {})
  local m = { "\\begin{minipage}{\\linewidth}\\centering",
              "\\pandocbounded{\\includegraphics[keepaspectratio]{" .. img.src .. "}}" }
  if #caption > 0 then
    m[#m + 1] = "\\par\\vspace{6pt}{\\bfseries " .. latex_of({ pandoc.Plain(caption) }) .. "}"
  end
  m[#m + 1] = "\\end{minipage}"
  return table.concat(m, "\n")
end

local function KeepTogether(blocks)
  local out = pandoc.Blocks({})
  local heading = nil   -- a Header held back until we know what follows it
  local function flush() if heading then out:insert(heading); heading = nil end end
  for _, b in ipairs(blocks) do
    local n = table_number(b)
    local measure = n and measures[n] or (b.t == "Figure" and heading and figure_measure(b)) or nil
    if measure then
      local extra = heading and "3\\baselineskip" or "0pt"
      out:insert(pandoc.RawBlock("latex", "\\docgenkeeptable{" .. extra .. "}{" .. measure .. "}"))
      flush()
      out:insert(b)
    elseif b.t == "Header" then
      flush(); heading = b
    else
      flush(); out:insert(b)
    end
  end
  flush()
  return out
end

-- Set `lot` / `lof` so the template prints a list of tables / figures only when the
-- document has captioned ones.
local function Lists(doc)
  local figures = 0
  doc:walk({ Figure = function(f)
    if #pandoc.utils.blocks_to_inlines(f.caption.long or {}) > 0 then figures = figures + 1 end
  end })
  if captioned_tables > 0 then doc.meta.lot = true end
  if figures > 0 then doc.meta.lof = true end
  return doc
end

return {
  { Meta = function(meta) header_color = meta["table-header-color"] ~= nil end },
  { Table = Table },
  { Blocks = KeepTogether },
  { Pandoc = Lists },
}
