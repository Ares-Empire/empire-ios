"""Move one invented payment; check its saved category and the source total."""
from decimal import Decimal
import re

# The server sample cannot save. The isolated phone sample imports invented CSVs.
# Rename through the existing sample driver: engine category names are not catalog
# keys, whereas these invented user category names stay verbatim in both languages.
SOURCE = 'Smoke groceries'
TARGET = 'Smoke target'
ARGS = ('-samplePhone', '-sampleOverview', '-sampleRenameCategory', 'groceries',
        '-categoryName', SOURCE, '-sampleOwn', TARGET)


def cents(text, language):
    value = re.findall(r'[−-]?\d[\d.,]*', text)[-1].replace('−', '-')
    value = value.replace('.', '').replace(',', '.') if language == 'de' else value.replace(',', '')
    return abs(int(Decimal(value) * 100))


def run(r):
    source = r.wait_for(SOURCE, literal=True, contains=True, type='Button')[0]
    before_label = source['AXLabel']
    before = cents(before_label, r.language)
    r.screenshot('before')
    r.tap(SOURCE, literal=True, contains=True, type='Button')
    r.wait_for('Monthly spend')
    # Dates are formatted data, not UI catalog keys. Use the first observed month
    # from this sample category; do not duplicate English/German month names.
    months = [e['AXLabel'] for e in r.visible() if e.get('type') == 'Button'
              and re.search(r'\b20\d\d\b', e.get('AXLabel') or '') and '€' in e['AXLabel']]
    r.require(bool(months), 'Sample category shows a month row with a total')
    month = months[0]
    r.tap(month, literal=True, type='Button')
    r.wait_for(id='selectPayments')
    payments = [e['AXLabel'] for e in r.visible() if e.get('type') == 'Button'
                and 'REWE Markt GmbH' in (e.get('AXLabel') or '')]
    r.require(bool(payments), 'Sample month shows a fictional REWE payment')
    payment = payments[0]
    amount = cents(payment, r.language)
    r.tap(payment, literal=True, type='Button')
    r.wait_for(id='changeCategory')
    r.tap(id='changeCategory')
    r.wait_for(id='saveCategory')
    r.tap(TARGET, literal=True, type='Button')
    r.expect(TARGET, literal=True, type='Button', child_id='checkmark')
    r.tap(id='saveCategory')
    r.wait_for('Only this one', type='Button')
    r.tap('Only this one', type='Button')
    r.expect(id='saveCategory', present=False)
    chip = r.wait_for(id='categoryChip')[0]
    r.require(chip['AXLabel'] == TARGET, f'Payment category is {TARGET!r}; observed {chip["AXLabel"]!r}')
    r.screenshot('payment-moved')
    r.tap('Done', type='Button', table='Shared')
    r.expect(id='changeCategory', present=False)
    r.tap(id='chevron.left', type='Button')
    r.expect(id='selectPayments', present=False)
    r.tap(id='chevron.left', type='Button')
    r.expect('Monthly spend', present=False)
    r.expect(before_label, literal=True, type='Button', present=False)
    source = r.wait_for(SOURCE, literal=True, contains=True, type='Button')[0]
    after = cents(source['AXLabel'], r.language)
    # Overview totals round to euros; the two rounded endpoints can differ by €1.
    r.require(before > after and abs((before - after) - amount) <= 100,
              f'Source total falls by the payment: before={before}c, after={after}c, payment={amount}c (rounding ≤100c)')
    r.tap(id='gearshape', type='Button')
    r.wait_for('Done', type='Button', table='Shared')
    r.tap('Done', type='Button', table='Shared')
    r.expect('Done', type='Button', table='Shared', present=False)
    r.screenshot('overview-after-settings')
