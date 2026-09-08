# Eco hero roster

These ten character portraits were prepared with the built-in ImageGen workflow for this project.

- The four original heroes were cleaned into isolated, full-body portraits while preserving their recognizable designs.
- Six new heroes were generated as polished Korean mobile-game chibi eco mascots with clean outlines, cel shading, and a bright energy-themed palette.
- New characters: Solar Fox Sol, Wind Rabbit Bori, Recycle Raccoon Ringo, Earth Turtle Tori, Lightning Bird Pika, and Mushroom Cat Momo.

All ten project assets now contain real alpha transparency. The six originally generated on a white matte and the fairy portrait with a baked checkerboard matte were processed with `res://scripts/tools/ExtractCharacterBackgrounds.gd`, which removes only near-neutral background pixels connected to the outer canvas. Runtime color-key shaders are intentionally not used, so white fur, clothing, eyes, and highlights remain opaque.

## Back-run animation sheets

The `sprites/back_run` directory contains a dedicated rear-view four-frame run cycle for every hero. Each sheet was generated with the built-in ImageGen workflow using the character portrait and existing forward animation as identity and layout references, then normalized to 2048×768 pixels (four 512×768 frames) with genuine alpha transparency.

`PlayerPawn.set_back_run_enabled(true)` selects these sheets while preserving the regular front-facing board animation. The Solar Panel Dash minigame enables rear-view running because the hero moves away from the camera.

## Side-run animation sheets

The `sprites/side_run` directory contains a right-facing four-frame side-view run cycle for all ten heroes. Each sheet was generated with the built-in ImageGen workflow using the corresponding portrait as an identity reference, then normalized to 2048×768 pixels (four 512×768 frames) with genuine alpha transparency.

`PlayerPawn.set_side_run_enabled(true)` selects these sheets. The Standby Power Hunt minigame uses them for left-to-right movement through the house; moving left mirrors the same sheet at runtime.
