#!/usr/bin/env python3
"""Renders the website's demo GIFs from scenes.html into docs/demos/.

    python3 scripts/demo-gifs/render.py            all scenes
    python3 scripts/demo-gifs/render.py grid zip   just these

Needs: pip install playwright && playwright install chromium, and ffmpeg (brew install ffmpeg).
"""
import pathlib, subprocess, sys, tempfile
from playwright.sync_api import sync_playwright

here = pathlib.Path(__file__).resolve().parent
out = here.parent.parent / "docs" / "demos"
FPS, SCALE = 20, 1.25
scenes = sys.argv[1:] or ["click", "search", "grid", "zip"]
out.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 960, "height": 600}, device_scale_factor=SCALE)
    for name in scenes:
        page.goto((here / "scenes.html").as_uri() + "?scene=" + name)
        page.wait_for_load_state("networkidle")
        dur = page.evaluate("SCENE_DUR")
        with tempfile.TemporaryDirectory() as tmp:
            n = int(dur * FPS)
            for i in range(n):
                page.evaluate(f"render({i / FPS})")
                page.locator("#screen").screenshot(path=f"{tmp}/{i:04d}.png")
            gif = out / f"{name}.gif"
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/%04d.png",
                            "-vf", "split[a][b];[a]palettegen=max_colors=200:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
                            "-loop", "0", str(gif)], check=True)
            poster = out / f"{name}.png"
            # A still for reduced-motion visitors and link previews: the most informative moment.
            still = {"click": 1.8, "search": 3.0, "grid": 2.8, "zip": 6.8}[name]
            page.evaluate(f"render({still})")
            page.locator("#screen").screenshot(path=str(poster))
        print(f"{gif.relative_to(out.parent.parent)}  {gif.stat().st_size // 1024} KB, {n} frames")
    browser.close()
