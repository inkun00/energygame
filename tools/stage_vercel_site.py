"""Stage the exported Godot game and its ranking function in one Vercel project."""
import argparse
from pathlib import Path
from shutil import copy2


def stage(web: Path, output: Path) -> None:
    service = Path(__file__).resolve().parents[1] / "services" / "room-directory"
    if output == web or output.is_relative_to(web):
        raise ValueError("Choose a staging folder outside the source export")
    if not all((web / name).is_file() for name in ("index.html", "index.pck", "index.wasm")):
        raise ValueError("Expected a complete Godot web export")
    public = output / "public"
    public.mkdir(parents=True, exist_ok=True)
    for source in web.iterdir():
        if source.is_file() and not source.name.startswith(".") and source.suffix != ".import":
            copy2(source, public / source.name)
    for name in ("package.json", "package-lock.json", "vercel.json",
                 "api/records.mjs", "src/scores.js", "src/firestore-connection.js", "src/firebase-scores.js"):
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        copy2(service / name, target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("web", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    stage(args.web.resolve(), args.output.resolve())
