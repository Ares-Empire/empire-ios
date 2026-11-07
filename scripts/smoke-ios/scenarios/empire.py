"""Rotate the ring, open province Details, and visit both shared settings pages."""
import json
from pathlib import Path


def run(r):
    r.wait_for(id='gearshape', type='Button')
    sample = json.loads((Path(__file__).resolve().parents[3] / 'Empire/Empire/Preview Content/empire.admin.json').read_text())
    provinces = {p['slug']: p for p in sample['projects']}
    # Aresium starts at the front. Rotate through the visible neighbor Aresus,
    # then Aresync. Its sample has no external URL, so a front tap opens Details.
    for slug, name in [('aresus', 'Aresus'), ('aresync', 'Aresync')]:
        r.tap(name, literal=True, contains=True, type='Button')
        r.wait_for(provinces[slug]['live'], literal=True, type='StaticText')
    r.tap('Aresync', literal=True, contains=True, type='Button')
    r.wait_for('Provinces', type='StaticText')
    r.screenshot('province-details')
    r.tap(id='xmark', type='Button')
    r.expect('Provinces', type='StaticText', present=False)
    r.tap(id='gearshape', type='Button')
    r.wait_for('Done', type='Button', table='Shared')
    r.tap('Appearance', contains=True, type='Button', table='Shared')
    r.wait_for('Light', type='Button', table='Shared')
    r.screenshot('appearance')
    r.tap(id='BackButton', type='Button')
    r.expect('Light', type='Button', table='Shared', present=False)
    r.tap('Language', contains=True, type='Button', table='Shared')
    r.wait_for('Like the iPhone', type='Button', table='Shared')
    r.screenshot('language')
    r.tap(id='BackButton', type='Button')
    r.expect('Like the iPhone', type='Button', table='Shared', present=False)
    r.tap('Done', type='Button', table='Shared')
    r.expect('Done', type='Button', table='Shared', present=False)
