-- columns.lua: multi-column text in the PDF.
--
--   <!-- columns 2 -->
--   ...paragraphs, lists...
--   <!-- columns end -->
--
-- The markers are HTML comments, so markdown editors ignore them; in LaTeX output they
-- become a multicols environment (the multicol package), which balances the text across
-- the columns. Tables and figures cannot sit inside the columns, so the build stops if
-- one is found between the markers. Runs after tables.lua.

if not FORMAT:match("latex") then return {} end

local function marker(block)
  if block.t ~= "RawBlock" or block.format ~= "html" then return nil end
  local n = block.text:match("^%s*<!%-%-%s*columns%s+(%d+)%s*%-%->%s*$")
  if n then return "begin", tonumber(n) end
  if block.text:match("^%s*<!%-%-%s*columns%s+end%s*%-%->%s*$") then return "end" end
  return nil
end

local function is_table_or_figure(block)
  if block.t == "Figure" or block.t == "Table" then return true end
  return block.t == "RawBlock" and block.format == "latex" and block.text:match("^%%docgen%-table:") ~= nil
end

function Blocks(blocks)
  local out = pandoc.Blocks({})
  local open = false
  for _, b in ipairs(blocks) do
    local kind, n = marker(b)
    if kind == "begin" then
      if open then error("docgen: '<!-- columns N -->' inside an open columns block") end
      if n < 2 then error("docgen: '<!-- columns N -->' needs N >= 2") end
      open = true
      out:insert(pandoc.RawBlock("latex", "\\begin{multicols}{" .. n .. "}"))
    elseif kind == "end" then
      if not open then error("docgen: '<!-- columns end -->' without a preceding '<!-- columns N -->'") end
      open = false
      out:insert(pandoc.RawBlock("latex", "\\end{multicols}"))
    else
      if open and is_table_or_figure(b) then
        error("docgen: a table or figure cannot be inside a columns block; close it with '<!-- columns end -->' first")
      end
      out:insert(b)
    end
  end
  if open then error("docgen: a columns block was not closed with '<!-- columns end -->'") end
  return out
end
