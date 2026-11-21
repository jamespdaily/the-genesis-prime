"""What the planted tools of the setup check's tests share.

NEXT_LINE is a bash function for a planted tool's script: a tool that answers differently on each
call reads the answers from a file of PLANT_DIR, one per line, and the counter file kept beside it.
"""

NEXT_LINE = """next_line() {  # next_line FILE COUNTER: the counter's next line of FILE, the last when they run out
  local n total
  n=$(cat "$PLANT_DIR/$2" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$PLANT_DIR/$2"
  total=$(grep -c '' "$PLANT_DIR/$1")
  [ "$n" -le "$total" ] || n=$total
  sed -n "${n}p" "$PLANT_DIR/$1"
}
"""
