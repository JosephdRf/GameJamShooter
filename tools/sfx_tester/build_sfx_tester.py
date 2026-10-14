"""Génère sfx_tester.html : interface pour écouter tous les sons du jeu et les candidats en ligne.

Usage (depuis la racine du projet) :
    python tools/sfx_tester/build_sfx_tester.py
puis ouvrir tools/sfx_tester/sfx_tester.html dans un navigateur.

- Sons du jeu : tous les .wav / .ogg / .mp3 de assets/audio/ (un groupe par dossier).
- Candidats en ligne : candidates.json (aperçus Freesound, licence CC0), écoutés en
  streaming sans téléchargement.
"""
import json
import os
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
EXTENSIONS = (".wav", ".ogg", ".mp3")


def local_sounds() -> list:
    groups = {}
    for folder, _, files in os.walk(AUDIO):
        for name in sorted(files):
            if not name.lower().endswith(EXTENSIONS):
                continue
            path = os.path.join(folder, name)
            duration = None
            if name.lower().endswith(".wav"):
                with wave.open(path) as w:
                    duration = round(w.getnframes() / w.getframerate(), 3)
            group = os.path.relpath(folder, AUDIO).replace(os.sep, "/")
            groups.setdefault(group, []).append({
                "title": name,
                "src": os.path.relpath(path, HERE).replace(os.sep, "/"),
                "res": "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/"),
                "dur": duration,
            })
    return [{"key": "local-" + g.replace("/", "-"), "label": g, "items": items} for g, items in sorted(groups.items())]


def main() -> None:
    with open(os.path.join(HERE, "candidates.json"), encoding="utf-8") as f:
        candidates = json.load(f)
    online = [{"key": k, "label": v["label"], "items": v["items"]} for k, v in candidates.items()]
    data = {"local": local_sounds(), "online": online}
    with open(os.path.join(HERE, "template.html"), encoding="utf-8") as f:
        page = f.read().replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    out = os.path.join(HERE, "sfx_tester.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    count = sum(len(g["items"]) for g in data["local"])
    print(f"{out} : {count} sons du jeu, {sum(len(g['items']) for g in online)} candidats en ligne")


if __name__ == "__main__":
    main()
