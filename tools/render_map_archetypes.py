#!/usr/bin/env python3
"""Render actual generated tiles and canonical runtime routes from topology.json."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

COLORS = {0: '#80b859', 1: '#4080e0', 2: '#1e591a', 3: '#d9b333', 4: '#bf4d59', 5: '#b3ad8c', 6: '#d8c59a', 7: '#73ad4d', 8: '#598c40'}
ROUTE_COLORS = ['#fff4c8', '#fa9c72', '#70e3de']
PANEL_W, PANEL_H = 760, 485

def font(size: int):
    for path in ['C:/Windows/Fonts/arial.ttf', '/System/Library/Fonts/Supplemental/Arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def point(tile, scale):
    x, y = tile
    return (PANEL_W / 2 + (x-y)*scale, 88+(x+y)*scale/2)

def panel(data):
    image=Image.new('RGB',(PANEL_W,PANEL_H),'#111d24')
    draw=ImageDraw.Draw(image)
    draw.text((22,15),data['name'],font=font(25),fill='#f2eee2')
    draw.text((22,49),f"Seed {data['seed']} | generated tiles + actual route paths",font=font(14),fill='#b6c5cd')
    side = max(len(data['grid']), len(data['grid'][0]))
    scale = min((PANEL_W - 60) / (2 * side), (PANEL_H - 150) / side)
    project = lambda tile: point(tile, scale)
    for y,row in enumerate(data['grid']):
        for x,tile in enumerate(row):
            cx,cy=project((x,y))
            draw.polygon([(cx,cy-scale/2),(cx+scale,cy),(cx,cy+scale/2),(cx-scale,cy)],fill=COLORS[tile])
    for index,route in enumerate(data['routes']):
        points=[project(tile) for tile in route['tiles']]
        if len(points)>1:
            draw.line(points,fill='#17252d',width=5)
            draw.line(points,fill=ROUTE_COLORS[index],width=2)
    for index,spawn in enumerate(data['spawns']):
        x,y=spawn
        corners=[project((x-.5,y-.5)),project((x+3.5,y-.5)),project((x+3.5,y+3.5)),project((x-.5,y+3.5))]
        color=['#7de6ff','#ff8c7e'][index]
        draw.polygon(corners,fill='#1c2d38',outline=color,width=2)
        center=project((x+1.5,y+1.5))
        draw.text((center[0]-9,center[1]-9),str(index+1),font=font(17),fill=color)
    metrics=data['metrics']
    draw.text((22,442),f"Woods {metrics['forest_tiles']} tiles | Water {metrics['water_tiles']} | Connected land {metrics['reachable_land_fraction']:.2%}",font=font(15),fill='#d0dbdd')
    draw.text((22,463),f"Opening trip difference <= {metrics['opening_trip_difference_seconds']:.3f}s | No fog or units shown",font=font(13),fill='#9cafb7')
    return image

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report',type=Path)
    parser.add_argument('--output',type=Path,default=Path('output/map-archetypes-2026-10-22'))
    parser.add_argument('--seed',type=int,help='Render one actual reported seed as a three-map row')
    args=parser.parse_args()
    maps=json.loads(args.report.read_text())['overview_maps']
    if args.seed is not None:
        maps=[data for data in maps if data['seed']==args.seed]
        if not maps: parser.error('Requested seed is not present in this report')
    args.output.mkdir(parents=True,exist_ok=True)
    seeds=sorted({m['seed'] for m in maps})
    sheet=Image.new('RGB',(PANEL_W*3,PANEL_H*len(seeds)+54),'#111d24')
    for m in maps:
        image=panel(m)
        image.save(args.output/f"map-{m['archetype']}-seed-{m['seed']}.png")
        sheet.paste(image,(PANEL_W*m['archetype'],PANEL_H*seeds.index(m['seed'])))
    draw=ImageDraw.Draw(sheet)
    y=PANEL_H*len(seeds)+17
    draw.text((22,y),'ROUTES:',font=font(16),fill='#e4e9e4')
    for index,name in enumerate(['Center','Upper flank','Lower flank']):
        x=130+index*200
        draw.line((x,y+9,x+35,y+9),fill=ROUTE_COLORS[index],width=3)
        draw.text((x+45,y),name,font=font(16),fill='#e4e9e4')
    draw.text((800,y),'Gold = gold mines | Red = food | Dark green = woods | Blue = water',font=font(16),fill='#c2cdd1')
    target=args.output/'map-contact-sheet.png'
    sheet.save(target)
    print(target.resolve())

if __name__=='__main__':
    main()
