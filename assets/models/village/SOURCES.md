# Energy fairy village

The village props were made for this game with [VAST-AI TripoSR](https://github.com/VAST-AI-Research/TripoSR) and Blender 4.5. The reference set includes ten original prop designs and the ten existing construction illustrations in `assets/buildings/`.

The trees, hills and completed facilities use cleaned and decimated surfaces from their individual TripoSR reconstructions. The hard-surface props use Blender retopology fitted to the reconstructed surfaces. Blender supplies the roof and window trim, bridge rails, open gate, solar cells and mechanical mounting points. Palette variants share the same scale. The layered island, paths and waterways are authored in Blender to fit the board and its bridges.

The construction models carry the names of the project illustrations. Each has an individually fitted footing and an embedded UV texture that combines the projected illustration with the colours of the reconstructed hidden surfaces. The scenery props use glTF vertex colours, which Godot enables through `ImportVillagePalette.gd`. Cottages, trees and equipment reuse the same meshes between placements.
