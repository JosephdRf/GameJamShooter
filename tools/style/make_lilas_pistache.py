"""Textures du style « lilas & pistache » de l'arène (arena5), à partir des textures d'origine.

Les textures de l'arène sont des aplats (carreaux, joints, planches) : chaque couleur d'origine
est remplacée par une couleur choisie (COLOR_MAPS). Un pixel entre deux couleurs (bord lissé
d'un carreau) est interpolé entre leurs deux remplaçantes, et ses petites variations sont
gardées : les dessins restent nets. Les étagères (bois photographique) sont seulement
éclaircies et désaturées.

Usage : python3 make_lilas_pistache.py <dossier des textures d'origine> <dossier de sortie>
(textures d'origine : PNG nommés comme leur matériau, exportés du GLB par Godot.)
"""
import os
import sys

import numpy as np
from PIL import Image

# Matériau -> [(couleur d'origine, couleur du style)]. Le noir (UV inutilisés) reste noir.
LILAS = {"blanc": "#FBF9FF", "peinture": "#F1ECFA", "clair": "#DCD0F4", "carreau": "#C8B6EE",
         "fonce": "#AE96E0"}
PISTACHE = {"blanc": "#F6FBF0", "1": "#E2F2D2", "2": "#CDE8B5", "3": "#B5DC97", "4": "#9CCB7E",
            "5": "#7FAF68", "6": "#5F8A55"}
BOIS_PISTACHE = [("#9c6c3c", "#C9DFB6"), ("#b46c3c", "#DCEACD"), ("#9c543c", "#B5D19E"),
                 ("#3c240c", "#55704C"), ("#6c3c24", "#7E9A6E"), ("#54240c", "#66805A"),
                 ("#845424", "#94B080"), ("#543c24", "#6C8560"), ("#9c6c54", "#C3D9AF"),
                 ("#9c5424", "#ABCB93")]
DAMIER_CITRON = [("#e46c24", "#F3D774"), ("#fcb43c", "#FFF3BE"), ("#e4b43c", "#F7E39A"),
                 ("#fcfccc", "#FFFDF0"), ("#fce4cc", "#FFFDF0"), ("#fcfce4", "#FFFDF0")]
COLOR_MAPS = {
    "M_cuit_Murs": [("#fcfce4", LILAS["peinture"]), ("#fcb43c", LILAS["carreau"]),
                    ("#e4b454", "#C1AEE8"), ("#e4b43c", "#C1AEE8"), ("#e46c24", LILAS["fonce"]),
                    ("#fce4b4", LILAS["clair"])],
    "M_cuit_Murs_Douche": [("#3c8484", PISTACHE["4"]), ("#548484", PISTACHE["3"]),
                           ("#6c8484", "#C3E3A8"), ("#6c846c", PISTACHE["2"]),
                           ("#84846c", "#D6EDC2"), ("#fcfce4", PISTACHE["blanc"])],
    "M_cuit_Sol_Douche": DAMIER_CITRON,
    "M_cuit_Marche_Douche": DAMIER_CITRON,
    "M_cuit_Placard": [("#e49c54", PISTACHE["2"]), ("#cc5424", PISTACHE["4"]),
                       ("#9c5424", PISTACHE["5"]), ("#6c3c24", PISTACHE["6"]),
                       ("#54240c", "#4E7347"), ("#cc843c", PISTACHE["3"])],
    "M_cuit_Panier_Linge": [("#cc9c54", "#BDE3A2"), ("#cc8454", "#A9D68B"),
                            ("#b48454", "#96C47A"), ("#b49c6c", "#C4E2AE")],
    "M_carton": [("#e4b46c", "#EAD3A4"), ("#cc843c", "#D9BB85"), ("#b46c24", "#C29F6A"),
                 ("#fccc9c", "#F7E9CB"), ("#9c6c24", "#A8875A"), ("#cc9c54", "#E0C694")],
    "M_cuit_Porte_L": BOIS_PISTACHE,
    "M_cuit_Porte_R": BOIS_PISTACHE,
    "M_cuit_Cadre": BOIS_PISTACHE,
    "M_cuit_Barreaux": BOIS_PISTACHE,
}
# Bois clair des étagères : teinte des veines sombres et du bois clair.
WOOD_DARK = "#B8906A"
WOOD_LIGHT = "#F3E4C8"
# Part des petites variations d'origine (grain, nuances d'un même carreau) gardée.
DETAIL = 0.35


def rgb(hex_color: str) -> np.ndarray:
    hex_color = hex_color.lstrip("#")
    return np.array([int(hex_color[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def remap(image: Image.Image, pairs: list) -> Image.Image:
    data = np.asarray(image.convert("RGBA"), dtype=np.float32)
    pixels = data[..., :3].reshape(-1, 3)
    sources = np.stack([rgb(s) for s, _ in pairs] + [np.zeros(3, np.float32)])
    targets = np.stack([rgb(t) for _, t in pairs] + [np.zeros(3, np.float32)])
    out = np.empty_like(pixels)
    for start in range(0, len(pixels), 1 << 20):
        p = pixels[start:start + (1 << 20)]
        dist = ((p[:, None, :] - sources[None, :, :]) ** 2).sum(-1)
        order = np.argsort(dist, axis=1)
        a, b = order[:, 0], order[:, 1]
        sa, sb, ta, tb = sources[a], sources[b], targets[a], targets[b]
        seg = sb - sa
        t = np.clip(((p - sa) * seg).sum(-1) / np.maximum((seg * seg).sum(-1), 1e-6), 0.0, 1.0)[:, None]
        base = sa + seg * t
        out[start:start + len(p)] = ta + (tb - ta) * t + (p - base) * DETAIL
    data[..., :3] = np.clip(out, 0, 255).reshape(data.shape[:2] + (3,))
    return Image.fromarray(data.astype(np.uint8))


def lighten_wood(image: Image.Image) -> Image.Image:
    """Bois des étagères : bois clair (dégradé WOOD_DARK -> WOOD_LIGHT selon la luminosité
    d'origine, qui garde le grain). Le bois d'origine, patiné et de teintes variées, tirait vers
    le gris et le rose une fois éclairci."""
    data = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    lum = data @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    lo, hi = np.percentile(lum, 2), np.percentile(lum, 98)
    t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0.0, 1.0)[..., None]
    out = rgb(WOOD_DARK) + (rgb(WOOD_LIGHT) - rgb(WOOD_DARK)) * t
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def main(source_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for name, pairs in COLOR_MAPS.items():
        remap(Image.open(os.path.join(source_dir, name + ".png")), pairs).save(
            os.path.join(out_dir, name + ".png"), optimize=True)
        print(name)
    shelf = Image.open(os.path.join(source_dir, "M_etagere.png")).resize((2048, 2048), Image.LANCZOS)
    lighten_wood(shelf).save(os.path.join(out_dir, "M_etagere.jpg"), quality=92)
    print("M_etagere")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
