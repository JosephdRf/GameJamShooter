# Éclairage de l'arène

`environnement_arene.tres` : ambiance (ciel crème, SSAO, reflets d'écran, glow, tonemap filmic).

Les lumières runtime (soleil par la fenêtre nord, appoint froid, plafonnier, douche, sonde de reflets) sont dans `res://scenes/levels/eclairage_arene.tscn`, instancié par `arena5.tscn`.

Pas de lightmaps : les ombres et l'AO cuit dans les textures suffisent, et un rebake Godot n'est pas nécessaire après un réexport du GLB.
