-- headers.lua: header/footer metadata helpers for the docgen template.
--
-- In any of the six header/footer slots (header-left, header-center, header-right,
-- footer-left, footer-center, footer-right) the token {page} is replaced by the
-- current page number. Metadata strings are otherwise LaTeX-escaped by pandoc, so
-- authors cannot write \thepage directly.

local slots = {
  "header-left", "header-center", "header-right",
  "footer-left", "footer-center", "footer-right",
}

local function expand_page_token(text)
  local inlines = pandoc.Inlines({})
  local pos = 1
  while true do
    local s, e = text:find("{page}", pos, true)
    if not s then
      if pos <= #text then inlines:insert(pandoc.Str(text:sub(pos))) end
      break
    end
    if s > pos then inlines:insert(pandoc.Str(text:sub(pos, s - 1))) end
    inlines:insert(pandoc.RawInline("latex", "\\thepage"))
    pos = e + 1
  end
  return inlines
end

function Meta(meta)
  for _, slot in ipairs(slots) do
    if meta[slot] ~= nil then
      local text = pandoc.utils.stringify(meta[slot])
      if text:find("{page}", 1, true) then
        meta[slot] = pandoc.MetaInlines(expand_page_token(text))
      end
    end
  end
  return meta
end
