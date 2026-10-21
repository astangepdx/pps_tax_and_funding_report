-- strip_heading_numbers.lua: drop a leading manual number ("1.", "1.2", "3.4.1.")
-- from every heading so --number-sections does not produce "1. 1. Background".
-- Enabled with STRIP_HEADING_NUMBERS=1; intended for legacy hand-numbered specs.

function Header(h)
  local first = h.content[1]
  if first and first.t == "Str" and first.text:match("^%d+[%.%d]*%.?$") then
    h.content:remove(1)
    while h.content[1] and h.content[1].t == "Space" do
      h.content:remove(1)
    end
  end
  return h
end
