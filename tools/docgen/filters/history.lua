-- history.lua: applied to history.md only. Every heading in the version-history page is
-- unnumbered and kept out of the table of contents, so the source can use a plain
-- "# Version History" heading without pandoc attribute braces.

function Header(h)
  h.classes:insert("unnumbered")
  h.classes:insert("unlisted")
  return h
end
