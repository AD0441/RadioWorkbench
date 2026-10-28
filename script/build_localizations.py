#!/usr/bin/env python3
"""Generate native UI strings from reviewed translations and Swift compiler keys.

Pass --extraction-path to a build made with -emit-localized-strings. Without it,
keep keys from the checked-in native catalog. No network or translation service.
"""
from pathlib import Path
import argparse,json,re
parser=argparse.ArgumentParser();parser.add_argument('--extraction-path');args=parser.parse_args()
root=Path(__file__).resolve().parent.parent/'Sources/RadioWorkbench/Resources'
table=json.loads((root/'Translations.json').read_text())
fmt=re.compile(r'%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:ll|l|z)?[diufgeG@]|%%')
def canonical(key):
    formats=[]
    def sub(m):
        if m[0]=='%%':return '%'
        formats.append(m[0]);return '{'+str(len(formats)-1)+'}'
    return fmt.sub(sub,key),formats
keys=set(k for k in table if '{' not in k)
existing=root/'en.lproj/Localizable.strings'
if existing.exists():
    for line in existing.read_text().splitlines():
        match=re.match(r'("(?:\\.|[^"\\])*")\s*=',line)
        if match:keys.add(json.loads(match[1]))
if args.extraction_path:
    for file in Path(args.extraction_path).rglob('*.stringsdata'):
        doc=json.loads(file.read_text())
        for item in doc.get('tables',{}).get('Localizable',[]):keys.add(item['key'])
missing=[]; catalogs={'es':{},'en':{}}
for key in sorted(keys):
    if key in table:english=table[key]
    else:
        template,formats=canonical(key)
        english=table.get(template,key)
        if english != key:
            english=english.replace('%','%%')
            for i,value in enumerate(formats):english=english.replace('{'+str(i)+'}',value)
        elif re.search(r'[áéíóúñ¿¡]|\b(?:Guardar|Selecciona|Mostrar|Entrada|Salida|Sin|Todos|Todas|Desde|Hasta|Avisos)\b',template):missing.append(template)
    catalogs['es'][key]=key;catalogs['en'][key]=english
for language,values in catalogs.items():
    output=root/(language+'.lproj');output.mkdir(exist_ok=True)
    (output/'Localizable.strings').write_text('/* Generated from reviewed Translations.json and compiler keys. */\n'+''.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';\n' for k,v in sorted(values.items())))
print(f'{len(table)} reviewed translations, {len(keys)} native keys, {len(set(missing))} Spanish keys awaiting review')
if missing:print('\n'.join(sorted(set(missing))))
