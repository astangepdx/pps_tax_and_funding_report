-- fallback.lua: set characters the main font may lack in the fallback font.
--
-- XeLaTeX has no automatic glyph fallback. When metadata sets `fallbackfont`, every run
-- of Greek (U+0370-03FF) or arrow (U+2190-21FF) characters in body text is wrapped in
-- {\docgenfallbackfont ...}, a font family the template defines from `fallbackfont`.
-- The group is closed right after the run, so this is safe inside table cells, headings
-- and bold/italic text (the fallback family keeps the current size, weight and shape).
-- Code and code blocks are untouched; the monospace font covers these characters.

if not FORMAT:match("latex") then return {} end

local function needs_fallback(cp)
  return (cp >= 0x0370 and cp <= 0x03FF) or (cp >= 0x2190 and cp <= 0x21FF)
end

local function split_str(s)
  local out = pandoc.Inlines({})
  local buf, fb = {}, false
  local function flush()
    if #buf == 0 then return end
    local text = table.concat(buf)
    if fb then
      out:insert(pandoc.RawInline("latex", "{\\docgenfallbackfont " .. text .. "}"))
    else
      out:insert(pandoc.Str(text))
    end
    buf = {}
  end
  for _, cp in utf8.codes(s) do
    local want = needs_fallback(cp)
    if want ~= fb then flush(); fb = want end
    buf[#buf + 1] = utf8.char(cp)
  end
  flush()
  return out
end

local enabled = false

return {
  { Meta = function(meta) enabled = meta.fallbackfont ~= nil end },
  { Str = function(el)
      if not enabled then return nil end
      for _, cp in utf8.codes(el.text) do
        if needs_fallback(cp) then return split_str(el.text) end
      end
      return nil
    end },
}
