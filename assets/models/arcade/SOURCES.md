# Energy arcade equipment

The nine GLBs were reconstructed from the nine isolated objects in [the original prop design sheet](source/prop-designs.webp). Each object received its own inference in the official [TripoSR](https://github.com/VAST-AI-Research/TripoSR) model. The reconstruction used source revision `107cefdc244c39106fa830359024f6a2f1c78871`, a 192³ density grid and isosurface threshold 25.

Blender 4.5.15 removed disconnected fragments, smoothed the isosurface, reduced triangle counts and aligned each prop to a centered ground pivot. The front surface uses the registered design paint. Side and rear textures use color sampled from the inferred three-dimensional field. Each GLB embeds its textures. The gameplay axes are +Y up and +Z toward the front. The in-game scale supplies the dimensions.

The school façade retains the depth of the reconstruction. A retopologized hip roof, framed side windows and recessed lobby keep its silhouette and doorway clear from the gameplay camera. The photovoltaic panel has an aluminum back, two mount channels and a junction box.

| Model | Gameplay use | Triangles |
| --- | --- | ---: |
| storage | Battery gauge, substation and generator housings | 1,750 |
| school | School entrance with a cut-through doorway and recessed interior | 3,166 |
| hopper | Renewable and fossil fuel delivery bins, with two enamel colors | 1,600 |
| shelter | School bus stop shelter and bench | 3,000 |
| cooler | Split air conditioner and airflow outlet | 1,150 |
| plug | Movable two-pin mains plug | 1,350 |
| panel | Tracking photovoltaic panel | 1,074 |
| nacelle | Wind turbine gearbox housing | 1,700 |
| sluice | Sluice valve with a separately pivoted handwheel | 2,188 |
