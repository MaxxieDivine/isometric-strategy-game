# CLAUDE.md

Turn-based isometric 4X strategy game inspired by Civilization II. Built in **Godot 4.7** with **GDScript** only (no C#, no GDExtension unless agreed first).

## Design pillars

Weigh every feature, system, and UI change against these. If a change works against one, raise it before building it.

1. **Every turn is quick, pays something off, and teases what's next.**
   - Keep the end-turn loop fast: no long AI waits, no modal popup spam. Batch notifications.
   - Every turn the player should get something (growth, progress, a discovery, a finished build) and see something coming (the next tech, a border about to touch, a city nearly grown).
   - Show progress toward upcoming things in the UI: turns left, progress bars, previews.
2. **Few systems, deep interactions: strategy, not micromanagement.**
   - Add a new system only when no existing one can be extended. Depth should come from systems affecting each other, not from adding more systems.
   - Pick sensible defaults and automate anything with an obvious right answer (worker tiles, citizen assignment, routine moves). The player decides direction; the game handles the busywork.
   - Expose a few meaningful choices, not many fiddly ones.
3. **Retro at heart, alive on screen.**
   - Classic isometric tile look and readable, chunky UI in the spirit of Civ II.
   - Make it feel alive with small motion and feedback: idle animations, water and ambient movement, tweens on unit moves, juicy feedback when something completes. Never let it slow down pillar 1, so animations must be skippable or fast.

## Narrative design
- Advisors are a core narrative system. There will be several, each with their own personality and agenda, and their story may tie into the rival AI civs.
- Early on they act as a tutorial and genuinely help. Later an advisor's advice may turn self-interested, annoying, or even malicious.
- So never assume advice is optimal or honest. Game systems produce options (e.g. `CitySiteScorer` ranks city sites); the advisor chooses what to say about them through a selection policy named in its data (`AdvisorPolicy`, only `"best"` so far).
- Keep advisors decoupled from rivals, but design nothing that would stop linking them later.
- Advisors only observe: `AdvisorDirector` reads game events and state and writes only `GameState.advisor`. Game rules never read advisor state, and dialogue randomness uses the advisor's own RNG, never `GameState.rng`, so advisor activity can't change any game outcome (`tests/test_advisor.gd` checks this).
- Advisors are data: `data/advisors/roster.json` lists the active ones; `data/advisors/<id>.json` holds name, title, portrait sprite key, personality, policies, phrases and dialogue triggers (event, conditions, once, cooldown, priority, carry_over, optional action, line variants with `{placeholders}` and a tone tag). Tune frequency there, not in code.
- Presentation is a character speaking: no "Tip"/"Tutorial" labels, never blocking, always dismissable, and the player can turn it off.

## Architecture rules

### Game state is plain data, separate from rendering
- All game state (map, tiles, units, cities, players, techs, turn counter, RNG seed) lives in plain data classes: `RefCounted`/`Resource`-free GDScript classes or Dictionaries/Arrays. It does **not** live in Nodes.
- Game logic (rules, turn processing, AI, combat resolution) works only on that data. It must not reference `Node`, scenes, sprites, `TileMapLayer`, or the scene tree, and must run headless.
- Rendering and UI only **read** state and send **commands/actions** (e.g. `MoveUnit`, `FoundCity`, `EndTurn`) to the logic layer. They never change state directly.
- Logic tells the view about changes through signals or an event list (e.g. `unit_moved`, `city_grew`). The view turns those events into animations.
- Every piece of state must be serializable to plain types (Dictionary/Array/String/int/float/bool) through explicit `to_dict()` / `from_dict()` methods. Do not save Nodes or Resources directly, and do not use `var_to_bytes` with objects.
- Use a seeded `RandomNumberGenerator` stored in game state for all gameplay randomness, so turns are reproducible and saves resume deterministically. Cosmetic-only randomness in the view may use its own RNG.

### Save files go in the project folder, not AppData
- Never use `user://` for saves (on Windows that resolves to AppData).
- Saves go in a `saves/` folder in the project directory:
  - In the editor or a debug run: `ProjectSettings.globalize_path("res://saves")`.
  - In exported builds `res://` is read-only, so use `OS.get_executable_path().get_base_dir().path_join("saves")`.
  - Wrap this in a single helper (e.g. `SaveSystem.get_save_dir()`) and create the folder with `DirAccess.make_dir_recursive_absolute` if it is missing.
  - **Web builds are the one exception**: a web page can only write to browser storage, so `SaveSystem.get_save_dir()` uses `user://saves` there (kept per browser and per site).
- Save format: JSON (human-readable, diffable), including a `version` field so old saves can be migrated.
- `systems/save_system.gd` (`SaveSystem`) does all save I/O. Loading validates the file and returns null for a broken, incomplete or newer-version save, so the game starts fresh instead of crashing.
- The game autosaves to `autosave.json` after every turn, on a new game, and when the app loses focus or closes, and continues the autosave on launch.
- `saves/` should be listed in `.gitignore`.

## Art and placeholders
- Data definitions (units, and later cities and yields) reference art by a `sprite` key, never by file path.
- `view/sprite_library.gd` resolves a key to `res://assets/sprites/<key>.png`. When no file exists, the view draws a code-generated placeholder from `view/placeholder_art.gd`. To add real art, drop in the PNG; no code changes needed.
- All placeholder drawing stays in the view layer.

## Web build
- `export_presets.cfg` has a single-threaded "Web" preset (no special server headers needed). `.github/workflows/deploy-web.yml` runs the tests, exports it and publishes it to GitHub Pages on every push to `main`. Keep its `GODOT_VERSION` in step with the editor.
- The page carries a `noindex` meta tag; the URL is shared, not advertised.
- Browsers have no system fonts to fall back on, so any symbol missing from Godot's built-in font draws as a box. `ui/symbol_font.gd` adds the bundled `assets/fonts/DejaVuSans.ttf` as a fallback; check new symbols in the web build.

## Isometric conventions
- Map data uses logical grid coordinates (`Vector2i`). Isometric projection (grid to screen and back) happens only in the view layer, in one place.
- Logic code never deals with pixel or screen coordinates.

## GDScript style
- Use static typing everywhere (`var hp: int`, `func foo(x: int) -> void`). Use `class_name` for data and logic classes.
- Follow the Godot style guide: `snake_case` for files, functions, and variables; `PascalCase` for classes and nodes; `CONSTANT_CASE` for constants.
- Prefer composition and small scripts. Keep autoloads to a minimum (e.g. one game/session manager and one save system), and don't use autoloads as a place to hold mutable game state by default. The state object belongs to the session.
- Keep balance numbers (unit stats, costs, yields, tech tree) in data files (`.json` or `.tres` definitions) instead of hard-coding them in logic.

## Suggested layout
```
core/       # pure data + rules: state, commands, turn processing, AI (no Nodes)
data/       # balance/definition files (units, terrain, techs, buildings)
view/       # scenes & scripts that render state: map, units, animations
ui/         # HUD, panels, menus
systems/    # glue: save/load, session manager, input → commands
saves/      # runtime save files (gitignored)
tests/      # headless tests for core/
```

## Testing
- `core/` logic must be testable headless (`godot --headless`). When adding rules, add or update tests that run turn processing on plain data with no scenes.
- Check save/load round-trips: `from_dict(to_dict(state))` should give an identical state.
- Run all tests with `.\tools\run_tests.ps1`, or a subset with `.\tools\run_tests.ps1 cities`. It reimports first, which refreshes the global class cache after new `class_name` scripts, then runs every suite and exits 1 on any failure. On Linux/macOS (and in CI) use `tools/run_tests.sh [filter]` with `GODOT` pointing at the Godot binary.
- Each `tests/test_*.gd` is a standalone `SceneTree` script that exits with code 1 on failure. A single suite can also be run directly:
  `D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_units.gd`
