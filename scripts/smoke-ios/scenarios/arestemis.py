"""Search sample listings, favorite one, and advance the tour to a price curve."""
TITLE = 'Helle 2-Zimmer-Wohnung mit Balkon in Schwabing'


def run(r):
    r.wait_for(id='gearshape', type='Button')
    r.tap('Listings', type='RadioButton')
    r.wait_for('Search listings', type='Button')
    r.tap('Search listings', type='Button')
    r.wait_for('Search by name or place', in_value=True, type='TextField')
    r.type('Schwabing')
    r.expect('Schwabing', literal=True, in_value=True, type='TextField')
    r.tap('ImmoScout24', literal=True, contains=True, type='Button')
    r.wait_for('Favorite', type='Button')
    r.expect(TITLE, literal=True)
    r.tap('Favorite', type='Button')
    r.wait_for('Remove from favorites', type='Button')
    r.screenshot('favorite-listing')
    r.tap(id='BackButton', type='Button')
    r.expect('Remove from favorites', type='Button', present=False)
    r.tap(id='BackButton', type='Button')
    r.expect('Schwabing', literal=True, in_value=True, type='TextField', present=False)
    r.tap('Hunts', type='RadioButton')
    r.wait_for(id='gearshape', type='Button')
    r.tap(id='gearshape', type='Button')
    r.wait_for('Done', type='Button', table='Shared')
    tour = dict(contains=True, type='Button')
    if not r.matches(r.tree, r.selector('Tour of Arestemis', **tour)):
        r.swipe()
        r.wait_for('Tour of Arestemis', **tour)
    r.tap('Tour of Arestemis', **tour)
    r.wait_for('Arestemis searches for you')
    titles = ('New search', 'A search', 'Listings → New', 'Listings → Searches',
              'A listing', 'Price monitor and Watch a website')
    for number, title in enumerate(titles, start=2):
        r.tap('Next', type='Button')
        r.wait_for(f'{number} / 8', literal=True)
        r.expect(title)
    r.tap('Nintendo Switch 2', literal=True, contains=True, type='Button')
    r.wait_for('Price history', ignore_case=True, contains=True)
    r.screenshot('tour-price-history')
    r.tap('Skip', type='Button')
    r.expect('7 / 8', literal=True, present=False)
