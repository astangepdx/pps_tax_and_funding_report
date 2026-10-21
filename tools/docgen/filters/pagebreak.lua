-- pagebreak.lua: a horizontal rule (a line containing only ---, *** or ___) becomes a
-- page break in the PDF. Editors render it as a rule, which is a visible marker; a raw
-- \newpage line also still works (markdown+raw_tex).

function HorizontalRule()
  if FORMAT:match("latex") then
    return pandoc.RawBlock("latex", "\\newpage")
  end
end
