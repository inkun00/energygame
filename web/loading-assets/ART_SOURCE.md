# Loading-screen illustration

- Created 2026-11-04 with the built-in `image_gen` tool.
- Original: `eco-heroes-loading-v1.png` (1536 × 1024).
- Web delivery: `eco-heroes-loading-v1.webp` (1280 × 853, WebP quality 86). Encoding and downscaling only; no visual elements were edited after generation.
- References: existing `assets/maps/energy_village_diorama.png` and Eco Heroes portraits `captain_eco.webp`, `solar_fox_sol.webp`, `water_popo.webp`, `wind_rabbit_bori.webp`.
- The WebP is embedded in `web/loading.html` so it appears before the Godot game pack downloads. This directory has `.gdignore` to avoid bundling the loading illustration again inside the game pack.
- The image contains no title or progress bar. These remain accessible HTML and use actual engine progress.

## Final prompt

```text
Use case: compositing / stylized-concept.
Asset type: finished illustrated key art for the loading screen of the Korean educational board-and-arcade game "Renewable Energy Explorers", for children ages 9–12.
Input images: image 1 is the existing game-map reference to transform into a lively welcoming key-art scene; images 2–5 are the four existing hero identity references, not separate panels.
Recompose the reference island as a beautiful polished 3:2 landscape game illustration (approximately 1536x1024). Retain the recognizable green mountain island, winding turquoise river, waterfall, wooden footbridge, golden circular board-game construction pads and friendly low-poly diorama feeling, but bring the camera lower and closer for a welcoming adventure illustration.
Place the four reference Eco Heroes together as a clear foreground team on the central curved stone path: the brown-haired boy in his green leaf suit and gold mask, the orange solar fox with yellow goggles and solar backpack, the round blue water-drop sprite with a gold tiara, and the white wind rabbit with turquoise goggles and scarf. Keep each hero's identifiable colors, face, costume and body proportions, translating them coherently into polished storybook game key art. They are excitedly welcoming the player, full bodies visible, each separate and readable. No extra characters. Avoid giving the child a fox face or changing the water sprite into a human.
Behind them show a small restored green village with blue solar-panel rooftops, two elegant three-bladed wind turbines on the hills, and a modest hydroelectric water channel using the waterfall's height. Include a few visible circular board tiles along the winding path so this clearly feels like this energy-learning adventure game. The energy technologies must be recognizable and grounded in the scene, not floating decorative icons.
Art direction: warm morning sun, lush emerald and mint, clear turquoise water and golden highlights, crisp friendly shapes, playful premium family adventure-game artwork, rich but uncluttered details. Let the dark teal outer corners blend naturally into the game's dark teal loading screen. Keep the central team and key energy features safely inside the central 85% of the canvas, with breathing room around heads and feet.
This is illustration only, not a screenshot or UI mockup: absolutely no text, letters, numbers, logos, interface widgets, loading bar, borders, watermark or leaf-logo badge. Existing title and real loading progress will be added separately by HTML. Opaque background.
```
