# Board models

The eleven board miniatures were modeled in Blender to match the construction materials shown in the inventory. The miniature wind rotor reuses the [Tripo Studio turbine blade](../wind/SOURCES.md), simplified for the board camera. The collection uses one embedded color palette. The game shares its meshes across tiles.

The finish-site tower crane is an original Blender model. Its mast, jib, hoist cable, and hook block were built and painted for the board. The game slews the jib and raises the suspended load with the cable.

The enamel board cell was reconstructed with the official TripoSR model from a newly rendered tile reference. Blender sampled cross-sections of the 87,300-triangle reconstruction, squared their registration to the board grid and retopologized the rolled lip and recessed face into a shared unit mesh. Godot applies each tile's type colour and scales the same mesh for the darker socket beneath it.
