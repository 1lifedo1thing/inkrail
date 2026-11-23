"""Verify the portable Windows ZIP and update the editor in historical Go releases."""

import argparse
import hashlib
import os
import shutil
from contextlib import contextmanager
from pathlib import Path
from tempfile import NamedTemporaryFile
from zipfile import ZIP_DEFLATED, ZipFile


HERE = Path(__file__).resolve().parent
SOUNDS = HERE.parents[1] / "Sources" / "Inkrail" / "Resources"
SAMPLES = ("key-1", "key-2", "key-3", "space", "erase", "return", "bell")


def correct_source(source, old, new, filename):
    if source.count(new) == 1:
        return source
    candidates = old if isinstance(old, tuple) else (old,)
    matches = [candidate for candidate in candidates if candidate in source]
    if len(matches) != 1 or source.count(matches[0]) != 1:
        raise ValueError(f"{filename} changed upstream. Review its implementation before packaging.")
    return source.replace(matches[0], new, 1)


def apply_sound_updates(source, root, changes):
    def replace(filename, old, new):
        name = root + "ui/" + filename
        content = changes[name] if name in changes else source.read(name)
        candidates = old if isinstance(old, tuple) else (old,)
        changes[name] = correct_source(content, tuple(candidate.encode() for candidate in candidates), new.encode(), name)

    changes[root + "ui/margin-bell.js"] = (HERE / "ui/margin-bell.js").read_bytes()
    first_import = "import {emphasis, markdownLines, shortcutAt, expandFormatting, compactFormatting}"
    replace("editor.js", first_import, "import {crossedBellPoint} from './margin-bell.js';\n" + first_import)
    replace("editor.js", "oldTop=scroller.scrollTop,previous=geometry();",
            "oldTop=scroller.scrollTop,previous=geometry(true);")
    signature = "  function replace(value,kind,withStyle=null,markers=false,stroke=null,newEndings=null) {"
    replace("editor.js", signature, """  function finishTypingStroke(value, start, eligible, previous, oldTop) {
    const after = geometry(true);
    if (previous && after && after.caretBottom + scroller.scrollTop > previous.caretBottom + oldTop + lineHeight() * .72) {
      onSound('carriage');
    } else if (eligible && crossedBellPoint(value, start, findPoint)) {
      onSound('bell');
    }
  }
""" + signature)
    replace("editor.js", """    const after=geometry();
    if(stroke==='key'||stroke==='space') if(previous&&after&&after.caretBottom+scroller.scrollTop>previous.caretBottom+oldTop+lineHeight()*.72) onSound('carriage');""",
            """    if (stroke === 'key' || stroke === 'space') {
      const directInsertion = (markers || value === '\\t') && !mark && a === b;
      finishTypingStroke(value, a, directInsertion, previous, oldTop);
    }""")
    replace("editor.js", "    compositionSnapshot=[...selection];composing=true;",
            "    compositionSnapshot={selection:[...selection], caret:geometry(true), offset:scroller.scrollTop};composing=true;")
    replace("editor.js", "    selection=compositionSnapshot;compositionSnapshot=null;",
            "    const {selection: original, caret, offset} = compositionSnapshot;\n"
            "    selection=original;compositionSnapshot=null;")
    commit = "    follow(true);updateFormat();onChange(snapshot());onSound('key');"
    replace("editor.js", commit, commit + "\n    finishTypingStroke(value, a, a === b, caret, offset);")
    replace("app.js", "if(k!=='navigation')desk.strike()", "if(k!=='navigation'&&k!=='bell')desk.strike()")
    replace("audio.js", "kind==='space'||kind==='erase'?kind:", "kind==='space'||kind==='erase'||kind==='bell'?kind:")
    previous_preview = "[120,'key-2'],[290,'space'],[370,'bell'],[720,'return']"
    original_preview = "[120,'key-2'],[290,'space'],[530,'return']"
    replace("audio.js", (original_preview, previous_preview), "[165,'key-2'],[350,'space'],[575,'bell'],[1180,'return']")
    replace("panels.js", "Give every keystroke its own character.",
            "The margin bell rings about seven character widths before the end of the line.")
    replace("panels.js", ("A few keys and a carriage return", "Keys, margin bell and carriage return"),
            "Keys, space bar, bell and return")

    changes[root + "ui/sound-profiles.js"] = (HERE / "ui/sound-profiles.js").read_bytes()
    changes[root + "notices/Sound-Credits.txt"] = (SOUNDS / "Sound-Credits.txt").read_bytes()
    replace("audio.js", "const styles=new Set(['classic','soft','crisp','portable','office','electric']);",
            "import {canonicalSound} from './sound-profiles.js';")
    replace("audio.js", "return new URL('./assets/'+(style==='classic'||!styles.has(style)?'':style+'-')",
            "style=canonicalSound(style);return new URL('./assets/'+(style==='classic'?'':style+'-')")
    panel_import = "import {mountDeskPreview} from './desk.js';"
    replace("panels.js", panel_import, "import {canonicalSound, soundProfiles} from './sound-profiles.js';\n" + panel_import)
    # Both the portable release and its first margin-bell update carry the old six choices.
    old_styles = ("[['classic','Classic','The original mechanical keys'],['soft','Soft','A quieter, softer touch'],"
                  "['crisp','Crisp','A bright, distinct strike'],['portable','Portable','Light, lively mechanical clatter'],"
                  "['office','Office','Weighty keys and a ringing bell'],['electric','Electric','A quick, precise powered snap']]")
    previous_styles = old_styles.replace("The original mechanical keys", "Dry typebar strikes").replace(
        "Weighty keys and a ringing bell", "Weighty keys and a deep return")
    replace("panels.js", (f"typewriterSound: titled({old_styles})", f"typewriterSound: titled({previous_styles})"),
            "typewriterSound: titled(soundProfiles)")
    value = "    const value = source?.[key];"
    replace("panels.js", value, value + "\n    if (key === 'typewriterSound') return [key, canonicalSound(value)];")

    for prefix in ("", "soft-", "royal-", "vintage-", "portable-", "electric-"):
        for sample in SAMPLES:
            filename = f"{prefix}{sample}.wav"
            changes[root + "ui/assets/" + filename] = (SOUNDS / filename).read_bytes()


def verify_manifest(source, manifest, root):
    hashes = {}
    for line in source.read(manifest).decode("utf-8").splitlines():
        checksum, relative = line.split("  ", 1)
        name = root + relative
        digest = hashlib.sha256()
        with source.open(name) as entry:
            while chunk := entry.read(1024 * 1024):
                digest.update(chunk)
        if name in hashes or digest.hexdigest() != checksum:
            raise ValueError(f"Invalid or duplicate checksum for {relative}")
        hashes[name] = checksum
    if hashes.keys() != {name for name in source.namelist() if name != manifest and not name.endswith("/")}:
        raise ValueError("The checksum manifest does not cover the complete release.")
    return hashes


@contextmanager
def atomic_output(output_path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=output_path.parent, delete=False) as temp:
        temporary = Path(temp.name)
    try:
        yield temporary
        os.replace(temporary, output_path)
    finally:
        temporary.unlink(missing_ok=True)


def correct_archive(source_path, output_path):
    if source_path.resolve() == output_path.resolve():
        raise ValueError("Choose a distinct output path to retain the original release.")
    with ZipFile(source_path) as source:
        names = source.namelist()
        manifests = [name for name in names if name.rsplit("/", 1)[-1] == "files.sha256"]
        if len(manifests) != 1 or len(names) != len(set(names)):
            raise ValueError("Expected one checksum manifest and unique ZIP entries.")
        manifest = manifests[0]
        root = manifest[:-len("files.sha256")]
        listed = verify_manifest(source, manifest, root)
        # The former Go distribution needs the historical source corrections.
        # Source-built releases already contain the editor for that exact tag.
        if root + "notices/go-runtime.txt" not in listed:
            with atomic_output(output_path) as temporary:
                shutil.copyfile(source_path, temporary)
            return
        changes = {}
        editor = root + "ui/editor.js"
        old = b"    value=normalized(value.text,value.style);\n    replace(value.text,null,value.style,false,null,value.endings);"
        changes[editor] = correct_source(source.read(editor), old, b"    if (!value.text) return;\n" + old, editor)
        markdown = root + "ui/markdown.js"
        old = b"    const escaped=isEscaped(s,a,start);\n    if(!code&&!escaped&&c==='[') {"
        new = b"    const escaped=isEscaped(s,a,start);\n    if (!code && escaped) continue;\n    if(!code&&!escaped&&c==='[') {"
        changes[markdown] = correct_source(source.read(markdown), old, new, markdown)
        apply_sound_updates(source, root, changes)
        retired = {root + f"ui/assets/{style}-{sample}.wav" for style in ("crisp", "office") for sample in SAMPLES}

        hashes = []
        for name, checksum in listed.items():
            if name in retired:
                continue
            if name in changes:
                checksum = hashlib.sha256(changes[name]).hexdigest()
            hashes.append(f"{checksum}  {name[len(root):]}\n")
        additions = sorted(changes.keys() - listed)
        for name in additions:
            hashes.append(f"{hashlib.sha256(changes[name]).hexdigest()}  {name[len(root):]}\n")
        changes[manifest] = "".join(hashes).encode("utf-8")

        with atomic_output(output_path) as temporary:
            with ZipFile(temporary, "w") as output:
                output.comment = source.comment
                for entry in source.infolist():
                    if entry.filename in retired:
                        continue
                    body = changes[entry.filename] if entry.filename in changes else source.read(entry)
                    output.writestr(entry, body)
                for name in additions:
                    output.writestr(name, changes[name], compress_type=ZIP_DEFLATED)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    correct_archive(args.source, args.output)
