class_name ArenaStyle
## Style « lilas & pistache » de l'arène (arena5) : remplace les couleurs du modèle Blender sans
## le modifier. Murs carrelés lilas (peinture blanc-lilas au-dessus), mosaïque de la douche en
## nuances de pistache, sol de douche en damier citron, placard, portes et panier pistache,
## carton kraft clair, étagères en bois clair, serviettes pastel, baignoire, toilettes et plafond
## blancs. Aucun bleu vif, rouge ni doré : ce sont les couleurs de l'eau, des équipes et des zones.
##
## Textures recolorées (mêmes dessins, autres couleurs) : assets/models/arene_bain/
## style_lilas_pistache/, générées par tools/style/make_lilas_pistache.py. Appliqué par
## arena5.gd au chargement (dans l'éditeur aussi) : un matériau copié par matériau d'origine,
## posé en surcharge sur chaque objet (rien n'est enregistré dans la scène).

const TEXTURE_DIR := "res://assets/models/arene_bain/style_lilas_pistache/"
## Matériau d'origine -> texture recolorée.
const TEXTURES := {
	"M_cuit_Murs": "M_cuit_Murs.png",
	"M_cuit_Murs_Douche": "M_cuit_Murs_Douche.png",
	"M_cuit_Sol_Douche": "M_cuit_Sol_Douche.png",
	"M_cuit_Marche_Douche": "M_cuit_Marche_Douche.png",
	"M_cuit_Placard": "M_cuit_Placard.png",
	"M_cuit_Panier_Linge": "M_cuit_Panier_Linge.png",
	"M_carton": "M_carton.png",
	"M_cuit_Porte_L": "M_cuit_Porte_L.png",
	"M_cuit_Porte_R": "M_cuit_Porte_R.png",
	"M_cuit_Cadre": "M_cuit_Cadre.png",
	"M_cuit_Barreaux": "M_cuit_Barreaux.png",
	"M_etagere": "M_etagere.jpg",
}
## Matériau d'origine -> couleur unie (les serviettes sont des aplats : couleur sans texture).
const COLORS := {
	"M_tong": Color("#F3D774"),
	"M_seche_cheveux_plastique": Color("#A9D68B"),
	"M_socle_seche_cheveux": Color("#C8B6EE"),
	"M_rebord_fenetre": Color("#FBE7A0"),
	"M_vasque": Color("#FBE7A0"),
	"M_baignoire": Color("#F7F7FA"),
	"M_toilettes": Color("#F7F7FA"),
	"M_plafond": Color("#FFFFFF"),
	"M_cuit_Serviette.001": Color("#B5DC97"),
	"M_cuit_Serviette.010": Color("#B5DC97"),
	"M_cuit_Serviette.002": Color("#C8B6EE"),
	"M_cuit_Serviette.011": Color("#C8B6EE"),
	"M_cuit_Serviette.003": Color("#FFFDF6"),
	"M_cuit_Serviette.012": Color("#FFFDF6"),
	"M_cuit_Serviette.004": Color("#FBE7A0"),
	"M_cuit_Serviette.013": Color("#FBE7A0"),
	"M_cuit_Serviette.005": Color("#E6DCFA"),
	"M_cuit_Serviette.006": Color("#AE96E0"),
}
## Objets qui gardent leur couleur d'origine malgré un matériau partagé : la marche de la zone
## d'apparition rouge (même matériau rouge que le socle du sèche-cheveux).
const KEEP := ["Marche_Penderie"]
## Émaillés (baignoire, toilettes) : blancs satinés, pas métalliques (trop brillants, ils
## reflétaient la pièce et paraissaient gris).
const ENAMEL := ["M_baignoire", "M_toilettes"]
## Bois mat : le matériau d'origine des étagères est métallique (reflets sombres sur le bois).
const MATTE := ["M_etagere"]
## Plafond : peu éclairé d'en bas, il restait sombre ; une légère lueur le garde blanc.
const CEILING := "M_plafond"
const CEILING_GLOW := 0.3


static func apply(root: Node) -> void:
	var styled := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name) in KEEP:
			continue
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if source == null:
				continue
			var key := source.resource_name
			if not (TEXTURES.has(key) or COLORS.has(key)):
				continue
			if not styled.has(key):
				styled[key] = _styled(source, key)
			mi.set_surface_override_material(s, styled[key])


static func _styled(source: StandardMaterial3D, key: String) -> StandardMaterial3D:
	var material := source.duplicate() as StandardMaterial3D
	if TEXTURES.has(key):
		material.albedo_texture = load(TEXTURE_DIR + TEXTURES[key])
		material.albedo_color = Color.WHITE
	else:
		material.albedo_texture = null
		material.albedo_color = COLORS[key]
	if key in ENAMEL:
		material.metallic = 0.0
		material.roughness = 0.45
		material.metallic_specular = 0.35
	if key in MATTE:
		material.metallic = 0.0
		material.metallic_texture = null
	if key == CEILING:
		material.emission_enabled = true
		material.emission = COLORS[key]
		material.emission_energy_multiplier = CEILING_GLOW
	return material
