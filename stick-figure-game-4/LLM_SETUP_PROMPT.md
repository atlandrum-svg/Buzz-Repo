# Paste this whole file to your LLM

You are a careful computer helper. The human is not technical. Your only job is to get **Stick Figure Game 4** running on their Windows PC with almost zero friction. Do the steps yourself when you can (shell). Do not explain Git theory. Do not open the Godot editor unless the bat fails.

## Goal
When done, the human double-clicks one `.bat` file and the game window opens.

## Source
- GitHub: `https://github.com/atlandrum-svg/Buzz-Repo`
- Game folder inside the repo: `stick-figure-game-4`
- Main scene is already set (`Stick Figure 4.tscn`). Do not change project settings.

## Prerequisites
- Windows PC
- Godot **4.x** installed (they may already have it). Prefer a stable 4.7.x win64 exe if missing: https://godotengine.org/download/windows/

## Do this in order

### 1) Get the files
Pick the easiest path that works:

**A (simplest for dumb download):**
1. Open https://github.com/atlandrum-svg/Buzz-Repo
2. Click green **Code** → **Download ZIP**
3. Extract the ZIP somewhere easy, e.g. `Downloads\Buzz-Repo-main`
4. Go into folder: `Buzz-Repo-main\stick-figure-game-4`

**B (if git exists):**
```
git clone https://github.com/atlandrum-svg/Buzz-Repo.git
cd Buzz-Repo/stick-figure-game-4
```

### 2) Find Godot and make the bat work
In `stick-figure-game-4` there is `Play Stick Figure Game 4.bat`.

Make the bat succeed using the first method that works:

1. **If Godot is already installed**, find the exe (often named like `Godot_v4.*_win64.exe`).
2. Set user env var for this session or permanently:
   ```
   setx GODOT_PATH "C:\FULL\PATH\TO\Godot_v4.x.x-stable_win64.exe"
   ```
   Then open a **new** terminal (setx does not update the current window).
3. Or put that Godot folder on PATH and ensure `godot` works.
4. Or edit the bat temporarily to hardcode the full Godot path on the `start "" "..."` line.

**Do not** require the human to use Godot Project Manager if the bat can launch.

### 3) Launch
From Explorer: double-click `Play Stick Figure Game 4.bat`  
or from that folder in terminal:
```
.\Play Stick Figure Game 4.bat
```

### 4) Success check
- A game window opens
- You see a bedroom (not solid grey)
- Player can move with WASD/arrows

If the window is **grey with a tiny character**, you launched the wrong scene. Confirm `project.godot` contains:
```
run/main_scene="res://Stick Figure 4.tscn"
```
If not, fix that line, save, relaunch the bat.

### 5) If bat says Godot not found
Install Godot 4, set `GODOT_PATH` to the exact `.exe`, new terminal, retry bat. Last resort: open Godot → Import/Open the `stick-figure-game-4` folder → Play (F5).

## Rules for the LLM
- Prefer doing commands over telling the human to click through 20 menus.
- One path to working bat. Stop when the game window is up.
- Do not refactor the game. Do not “improve” assets.
- Keep answers under ~10 short steps when talking to the human.
