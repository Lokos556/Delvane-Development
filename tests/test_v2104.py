from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def test_bulk_rate_rows_explicitly_use_stacked_layout():
    css=(ROOT/'static'/'styles.css').read_text(encoding='utf-8')
    start=css.index('/* Rosa V2.10.6')
    rules=css[start:]
    assert '.ari-bulk-row{display:block;' in rules
    assert '.ari-bulk-fields{display:grid;grid-template-columns:1fr 1fr;' in rules
    assert '.ari-bulk-restrictions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));' in rules
