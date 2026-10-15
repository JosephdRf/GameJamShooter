# Arène salle de bain (GLB)

Écrit par `scene/pipeline/cuisson_export.ps1`. Relancer ce script pour recuire / réexporter.

Godot réimporte tout seul (`arene_bain.glb.import`) : collisions via `tools/arena_glb_post_import.gd` (sauf l'eau). Les textures restent embarquées dans le GLB pour qu'un réexport n'éparpille pas de fichiers.
