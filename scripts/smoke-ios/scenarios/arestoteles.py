"""Search a sample topic, visit the other tabs, and keep a quick note waiting."""
# The normal sample accepts quick notes immediately. Its offline sample keeps
# the cached invented vault searchable and the note visibly waiting on the phone.
ARGS = ('-sampleOffline',)
# AXe sends physical keys; this text avoids punctuation and Y/Z layout changes.
NOTE = 'Smoke sample note 244'


def run(r):
    r.wait_for('Search positions', in_value=True)
    r.tap('Topics', type='RadioButton')
    r.wait_for('Search topics', in_value=True)
    r.tap('Search topics', type='TextField', in_value=True)
    r.type('Printing')
    r.expect('Printing', literal=True, type='TextField', in_value=True)
    r.tap('Printing press', literal=True, contains=True, type='Button')
    r.wait_for('Brief', type='Button')
    r.expect('Printing press', literal=True, type='Heading')
    r.screenshot('searched-note')
    r.tap(id='BackButton', type='Button')
    r.expect('Brief', type='Button', present=False)
    r.swipe(start=(200, 460), end=(200, 240))
    r.expect(id='space', present=False)
    r.tap('Library', type='RadioButton')
    r.wait_for('Search the library', in_value=True)
    # The system's search-role tab says “Suchen” in German, while the app's
    # Search key is “Suche”. Its existing symbol identifier is language neutral.
    r.tap(id='magnifyingglass', type='RadioButton')
    r.wait_for("Search titles, summaries, the notes' text and the glossary, in English and German.")
    r.tap('Positions', type='RadioButton')
    r.wait_for('Search positions', in_value=True)
    r.tap('Quick note', type='Button')
    r.wait_for('A thought for the Inbox', type='TextField', in_value=True)
    # The sheet focuses this field itself.
    r.type(NOTE)
    r.expect(NOTE, literal=True, type='TextField', in_value=True)
    r.tap('Save', type='Button')
    r.expect('Save', type='Button', present=False)
    r.wait_for('%lld quick notes waiting to be sent', count=1)
    r.tap('Quick note', type='Button')
    r.wait_for('Not sent yet', ignore_case=True)
    r.expect(NOTE, literal=True, contains=True, type='StaticText')
    r.expect('Waiting to be sent')
    r.screenshot('quick-note-waiting')
    r.tap('Close', type='Button')
    r.expect('Save', type='Button', present=False)
