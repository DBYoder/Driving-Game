# Notes for Claude

## Testing
- Run the GDScript unit tests (`godot --headless --path game -s res://tests/run_tests.gd`)
  and the Python tests (`python -m pytest tools/tests`) for every change.
- Only run the full QA test drives (`--qa-drive`, `--qa-stress`, `--qa-cops`, `--qa-deer`,
  `--qa-menus` on both routes) when a change significantly alters a route itself: a
  re-bake of the road or terrain, a new or moved start or finish, new roads or junctions
  the drive goes through. For anything else (car models, signs, landmarks, menus, docs),
  the unit tests and a few targeted screenshots are enough. CI still runs its own QA set.
- Don't regenerate the committed docs screenshots unless asked; CI takes fresh ones each run.
