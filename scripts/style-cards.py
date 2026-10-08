"""Generate the approved warm-paper deck from preserved upstream SVG artwork."""
from pathlib import Path
import xml.etree.ElementTree as ET
import copy
import os
import json
import subprocess
import tempfile
import re

NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
def tag(name): return '{'+NS+'}'+name
symbols = {
'C': 'M 0,-12 a 6,6 0 1,1 0,12 a 6,6 0 1,1 0,-12 Z M -6,-3 a 6,6 0 1,1 0,12 a 6,6 0 1,1 0,-12 Z M 6,-3 a 6,6 0 1,1 0,12 a 6,6 0 1,1 0,-12 Z M 0,-2 a 4,4 0 1,1 0,8 a 4,4 0 1,1 0,-8 Z M -1,4 C -1,8 -2,11 -4,12 L 4,12 C 2,11 1,8 1,4 Z',
'D': 'M 0,-12 L 9,0 L 0,12 L -9,0 Z',
'H': 'M 0,11 C -4,6 -12,1 -10,-5 C -8,-12 -2,-11 0,-6 C 2,-11 8,-12 10,-5 C 12,1 4,6 0,11 Z',
'S': 'M 0,-12 C -2,-7 -11,-2 -10,4 C -9,10 -3,10 -1,5 L -3,12 L 3,12 L 1,5 C 3,10 9,10 10,4 C 11,-2 2,-7 0,-12 Z'
}
output = Path('App/CardSources/Adjusted')
output.mkdir(parents=True, exist_ok=True)
for name in [rank+suit for suit in 'CDHS' for rank in ['A','2','3','4','5','6','7','8','9','10','J','Q','K']]:
    tree = ET.parse(Path('App/CardSources/cards-svg')/(name+'.svg'))
    root = tree.getroot()
    rank, suit = name[:-1], name[-1]
    color = '#c51d2b' if suit in 'DH' else '#171b20'
    art = ET.Element(tag('g'), {'transform':'translate(8.3543457 12.1333496) scale(0.9)'})
    face = rank in ['J','Q','K']
    if face:
        art.set('transform', 'translate(-8.3543457 -12.1333496) scale(1.10)')
    elif rank != 'A':
        # Scale uniformly to 88% of the original, around the card center.
        art.set('transform', 'translate(10.0252148 14.5600195) scale(0.88)')
    candidates = []
    for child in list(root):
        local = child.tag.split('}')[-1]
        if local in ['metadata','defs','namedview']: continue
        if child.get('id') == 'Layer_x0020_1':
            # Preserve the full-size rounded background; inspect all other art.
            for item in list(child):
                if item.get('id') != 'path5':
                    child.remove(item)
                    candidates.append(item)
            continue
        root.remove(child)
        if local != 'text': candidates.append(child)
    with tempfile.TemporaryDirectory(prefix='freecell-vector-bounds-') as directory:
        files = []
        for i, child in enumerate(candidates):
            probe = copy.deepcopy(root)
            for item in list(probe):
                if item.tag.split('}')[-1] not in ['defs']: probe.remove(item)
            probe.append(copy.deepcopy(child))
            file = Path(directory)/f'{i}.svg'
            ET.ElementTree(probe).write(file, encoding='utf-8')
            files.append(str(file))
        bounds = json.loads(subprocess.check_output([
            os.environ.get('NODE_BINARY', 'node'),
            'scripts/svg-art-bounds.cjs', *files], text=True))
    for child, box in zip(candidates, bounds):
        if box is None: continue
        x0,y0,x1,y1 = box
        is_corner = (x1 < 38 and y1 < 67) or (x0 > 129 and y0 > 175)
        # Face-card suit ornaments are replaced by the unified corner symbols.
        is_face_ornament = face and child.get('id', '').startswith('layer1')
        if not is_corner and not is_face_ornament: art.append(child)
    # Warm paper: broad ivory center plus a faint, asymmetric amber wash.
    defs = root.find(tag('defs'))
    if defs is None: defs = ET.SubElement(root, tag('defs'))
    paper = ET.SubElement(defs, tag('radialGradient'), {
        'id':'freecell-paper', 'cx':'43%', 'cy':'36%', 'r':'76%'})
    for offset, paper_color in [('0%', '#f5eddb'), ('48%', '#eee4cf'), ('100%', '#e3d3b2')]:
        ET.SubElement(paper, tag('stop'), {'offset':offset, 'stop-color':paper_color})
    wash = ET.SubElement(defs, tag('radialGradient'), {
        'id':'freecell-paper-wash', 'cx':'85%', 'cy':'82%', 'r':'68%'})
    ET.SubElement(wash, tag('stop'), {'offset':'0%', 'stop-color':'#dfc68e', 'stop-opacity':'0.13'})
    ET.SubElement(wash, tag('stop'), {'offset':'100%', 'stop-color':'#dfc68e', 'stop-opacity':'0'})
    background = next(element for element in root.iter() if element.get('id') == 'path5')
    background.set('style', 'fill:url(#freecell-paper);stroke:#685e4b;stroke-opacity:0.32;stroke-width:0.5')
    overlay = copy.deepcopy(background)
    overlay.set('id', 'freecell-paper-overlay')
    overlay.set('style', 'fill:url(#freecell-paper-wash);stroke:none')
    root.find(tag('g')).append(overlay)
    tint = ET.SubElement(defs, tag('filter'), {'id':'freecell-ivory-image', 'color-interpolation-filters':'sRGB'})
    transfer = ET.SubElement(tint, tag('feComponentTransfer'))
    for channel, slope in [('R', 238/255), ('G', 228/255), ('B', 207/255)]:
        ET.SubElement(transfer, tag('feFunc'+channel), {'type':'linear','slope':str(slope)})
    for element in art.iter(tag('image')):
        element.set('filter', 'url(#freecell-ivory-image)')
    # Remove upstream near-white backdrop shapes behind the ace illustrations.
    for parent in art.iter():
        for element in list(parent):
            if element.get('id', '').startswith('rect') and 'fill:#fffeff' in element.get('style', '').lower():
                parent.remove(element)
    # Blend the illustration's white regions into the surrounding ivory paper.
    for element in art.iter():
        if element.get('style'):
            element.set('style', re.sub(r'fill:\s*#(?:ffffff|fff)(?=;|$)',
                                      'fill:#eee4cf', element.get('style'), flags=re.I))
        if element.get('fill', '').lower() in ['white', '#fff', '#ffffff']:
            element.set('fill', '#eee4cf')
    if face:
        for parent in art.iter():
            for element in list(parent):
                # Upstream rounded portrait outline; preserve internal linework.
                if element.get('id') == 'path5-8':
                    parent.remove(element)
    root.append(art)
    for transform in ['', 'translate(167.0869141 242.6669922) rotate(180)']:
        corner = ET.SubElement(root,tag('g'),{'transform': transform, 'fill':color})
        text = ET.SubElement(corner,tag('text'),{'x':'25','y':'34','text-anchor':'middle','font-family':'Arial, sans-serif','font-weight':'700','font-size':'26' if rank=='10' else '29'})
        text.text = rank
        ET.SubElement(corner,tag('path'),{'d':symbols[suit],'transform':'translate(25 49) scale(0.72)'})
    tree.write(output/(name+'.svg'), encoding='utf-8',xml_declaration=True)
print('Created 52 approved warm-paper SVGs.')
