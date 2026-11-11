#!/usr/bin/env python3
"""Generate privacy-safe synthetic MRZ strips and benchmark installed Tesseract OCR.

These are synthetic text strips, not reproductions of government identity documents.
Requires Pillow and the `tesseract` executable. No network or real identity data is used.
"""
from __future__ import annotations
import json, shutil, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parent / "synthetic_mrz_benchmark"
IMAGES = ROOT / "images"


def check_digit(value: str) -> str:
    weights = (7, 3, 1)
    def val(ch: str) -> int:
        if ch == '<': return 0
        if ch.isdigit(): return int(ch)
        if 'A' <= ch <= 'Z': return ord(ch) - 55
        return 0
    return str(sum(val(c) * weights[i % 3] for i, c in enumerate(value)) % 10)


def td3() -> list[str]:
    l1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<'
    doc, dob, expiry = 'L898902C3', '740812', '120415'
    l2 = doc + check_digit(doc) + 'UTO' + dob + check_digit(dob) + 'F' + expiry + check_digit(expiry) + 'ZE184226B' + check_digit('ZE184226B')
    composite = l2[0:10] + l2[13:20] + l2[21:43]
    l2 = l2[:43] + check_digit(composite)
    return [l1[:44].ljust(44, '<'), l2[:44].ljust(44, '<')]


def td1() -> list[str]:
    # ICAO TD1 sample identity fields with valid document-number/date/composite digits.
    a = 'I<UTOD23145890' + check_digit('D23145890') + '<<<<<<<<<<<<<<<'
    b = '740812' + check_digit('740812') + 'F' + '120415' + check_digit('120415') + 'UTO' + '<<<<<<<<<<<' + '6'
    c = 'ERIKSSON<<ANNA<MARIA<<<<<<<<<<'
    # Composite digit for TD1 positions 6-30, line2 1-7, 9-15, 19-29.
    composite = a[5:30] + b[0:7] + b[8:15] + b[18:29]
    b = b[:29] + check_digit(composite)
    return [a[:30].ljust(30, '<'), b[:30].ljust(30, '<'), c[:30].ljust(30, '<')]


def td2() -> list[str]:
    l1 = 'I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<'
    doc, dob, expiry = 'D23145890', '740812', '120415'
    l2 = doc + check_digit(doc) + 'UTO' + dob + check_digit(dob) + 'F' + expiry + check_digit(expiry) + '<<<<<<<<<<<<'
    composite = l2[0:10] + l2[13:20] + l2[21:35]
    l2 = l2[:35] + check_digit(composite)
    return [l1[:36].ljust(36, '<'), l2[:36].ljust(36, '<')]


def levenshtein(a: str, b: str) -> int:
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def get_font(size: int):
    candidates = ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf']
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def render(lines: list[str], scenario: str, output: Path) -> None:
    longest = max(map(len, lines))
    font = get_font(28)
    probe = Image.new('RGB', (10, 10), 'white')
    d = ImageDraw.Draw(probe)
    bbox = d.textbbox((0, 0), 'M' * longest, font=font)
    line_h = max(32, bbox[3] - bbox[1] + 8)
    im = Image.new('RGB', (max(900, bbox[2] + 48), line_h * len(lines) + 36), (255, 255, 255))
    draw = ImageDraw.Draw(im)
    for i, line in enumerate(lines):
        draw.text((20, 12 + i * line_h), line, font=font, fill=(10, 10, 10))
    if scenario == 'low_contrast':
        im = ImageEnhance.Contrast(im).enhance(0.38)
        im = Image.blend(im, Image.new('RGB', im.size, (230, 230, 230)), 0.25)
    elif scenario == 'blur':
        im = im.filter(ImageFilter.GaussianBlur(radius=1.35))
    elif scenario == 'small':
        im = im.resize((im.width // 2, im.height // 2), Image.Resampling.LANCZOS)
    elif scenario == 'glare':
        overlay = Image.new('RGBA', im.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.ellipse((im.width * .50, -im.height * .65, im.width * 1.02, im.height * .80), fill=(255, 255, 255, 205))
        im = Image.alpha_composite(im.convert('RGBA'), overlay).convert('RGB')
    elif scenario == 'skew':
        im = im.rotate(4, resample=Image.Resampling.BICUBIC, expand=True, fillcolor='white')
    im.save(output, quality=93)


def main() -> None:
    if not shutil.which('tesseract'):
        raise SystemExit('Tesseract not found; generate images only, or install Tesseract to measure OCR.')
    IMAGES.mkdir(parents=True, exist_ok=True)
    docs = {'TD3': td3(), 'TD1': td1(), 'TD2': td2()}
    scenarios = ['clean', 'low_contrast', 'blur', 'small', 'glare', 'skew']
    manifest = []
    for fmt, lines in docs.items():
        for scenario in scenarios:
            name = f'{fmt.lower()}_{scenario}.png'
            path = IMAGES / name
            render(lines, scenario, path)
            proc = subprocess.run(['tesseract', str(path), 'stdout', '--psm', '6'], capture_output=True, text=True, timeout=30)
            observed = [''.join(c for c in line.upper() if c.isalnum() or c == '<') for line in proc.stdout.splitlines()]
            observed = [x for x in observed if x]
            truth = [''.join(c for c in line if c.isalnum() or c == '<') for line in lines]
            truth_flat = ''.join(truth)
            observed_flat = ''.join(observed)
            errors = levenshtein(truth_flat, observed_flat)
            manifest.append({
                'image': f'images/{name}', 'format': fmt, 'scenario': scenario,
                'ground_truth_lines': truth, 'ocr_lines': observed,
                'line_count_match': len(observed) == len(truth),
                'exact_line_match': observed == truth,
                'character_error_rate': round(errors / max(1, len(truth_flat)), 4),
                'tesseract_exit_code': proc.returncode,
            })
    exact = sum(x['exact_line_match'] for x in manifest)
    mean_cer = sum(x['character_error_rate'] for x in manifest) / max(1, len(manifest))
    report = {
        'title': 'Rosa synthetic MRZ OCR benchmark',
        'privacy': 'Synthetic specimen identity data only; no real document photos or personal data.',
        'scope_note': 'Benchmarks generic MRZ text-strip OCR; does not validate full-card localization or Hungarian visual fields.',
        'engine': subprocess.run(['tesseract', '--version'], capture_output=True, text=True).stdout.splitlines()[0],
        'cases': len(manifest), 'exact_document_reads': exact,
        'exact_document_read_rate': round(exact / len(manifest), 4) if manifest else 0,
        'mean_character_error_rate': round(mean_cer, 4),
        'results': manifest,
    }
    (ROOT / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    summary = [
        '# Synthetic MRZ OCR benchmark', '',
        f"- Engine: `{report['engine']}`", f"- Cases: {report['cases']}",
        f"- Exact line-set reads: {exact}/{len(manifest)} ({report['exact_document_read_rate']:.1%})",
        f"- Mean character error rate (CER): {mean_cer:.1%}", '',
        '> Synthetic text strips only. These figures are not a real-document accuracy claim and do not measure full-card detection.', '',
        '| Format | Scenario | Exact read | CER | OCR output |', '|---|---|---:|---:|---|'
    ]
    for item in manifest:
        shown = ' / '.join(item['ocr_lines']).replace('|', '\\|') or '(no text)'
        summary.append(f"| {item['format']} | {item['scenario']} | {'yes' if item['exact_line_match'] else 'no'} | {item['character_error_rate']:.1%} | `{shown[:110]}` |")
    (ROOT / 'README.md').write_text('\n'.join(summary) + '\n', encoding='utf-8')
    print(f"Benchmark complete: {exact}/{len(manifest)} exact reads ({report['exact_document_read_rate']:.1%}); mean CER {mean_cer:.1%}.")
    print(f"Results: {ROOT / 'README.md'}")

if __name__ == '__main__':
    main()
