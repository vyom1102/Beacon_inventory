import json
import sqlite3
import io
import zipfile
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, quote
from xml.sax.saxutils import escape

ROOT = Path(__file__).parent
DB = ROOT / 'beacons.db'

def connection():
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row
    db.execute('''CREATE TABLE IF NOT EXISTS scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        direction TEXT NOT NULL CHECK(direction IN ('in','out')),
        venue TEXT NOT NULL,
        reason TEXT NOT NULL,
        scanned_at TEXT NOT NULL
    )''')
    db.execute('CREATE INDEX IF NOT EXISTS scans_barcode ON scans(barcode, id DESC)')
    return db

def rows():
    with connection() as db:
        return [dict(r) for r in db.execute('SELECT * FROM scans ORDER BY id DESC')]

def cell(value):
    return '<c t="inlineStr"><is><t xml:space="preserve">' + escape(str(value)) + '</t></is></c>'

def make_xlsx(records):
    headers = ['Scan time (UTC)', 'Barcode', 'Status', 'Venue name', 'Reason']
    data = [headers] + [[r['scanned_at'], r['barcode'], r['direction'].upper(), r['venue'], r['reason']] for r in records]
    sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
    sheet += ''.join(f'<row r="{i}">' + ''.join(cell(v) for v in row) + '</row>' for i, row in enumerate(data, 1))
    sheet += '</sheetData></worksheet>'
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml', '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Scan log" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml', sheet)
    return output.getvalue()

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'public'), **kwargs)

    def send_json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/api/scans':
            records = rows()
            latest = {}
            for r in records:
                latest.setdefault(r['barcode'], r)
            return self.send_json(200, {'scans': records[:200], 'beacons': list(latest.values()), 'movement_count': len(records)})
        if path == '/api/export':
            body = make_xlsx(list(reversed(rows())))
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            self.send_header('Content-Disposition', 'attachment; filename="beacon-scans.xlsx"')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            return self.wfile.write(body)
        return super().do_GET()

    def do_POST(self):
        if urlparse(self.path).path != '/api/scans':
            return self.send_json(404, {'error': 'Not found'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length > 8192:
                return self.send_json(413, {'error': 'Request too large'})
            data = json.loads(self.rfile.read(length))
            barcode = str(data.get('barcode', '')).strip()
            direction = data.get('direction')
            venue = str(data.get('venue', '')).strip()
            reason = str(data.get('reason', '')).strip()
            if not barcode or len(barcode) > 150 or direction not in ('in', 'out') or not venue or not reason or len(venue) > 150 or len(reason) > 300:
                return self.send_json(400, {'error': 'Enter a barcode, venue name, reason, and In or Out.'})
            with connection() as db:
                previous = db.execute('SELECT direction FROM scans WHERE barcode=? ORDER BY id DESC LIMIT 1', (barcode,)).fetchone()
                if previous and previous['direction'] == direction:
                    return self.send_json(409, {'error': f'This beacon is already {direction.upper()}. Choose the other status.'})
                now = datetime.now(timezone.utc).isoformat(timespec='seconds')
                db.execute('INSERT INTO scans (barcode,direction,venue,reason,scanned_at) VALUES (?,?,?,?,?)', (barcode, direction, venue, reason, now))
            return self.send_json(201, {'barcode': barcode, 'direction': direction, 'scanned_at': now})
        except (ValueError, TypeError, json.JSONDecodeError):
            return self.send_json(400, {'error': 'Invalid request'})

if __name__ == '__main__':
    with connection():
        pass
    print('Beacon Inventory: http://localhost:8000', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8000), Handler).serve_forever()
