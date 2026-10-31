const $ = id => document.getElementById(id);
let direction = 'in';
let beacons = new Map();
let scanner = null;
let scanning = false;

function setDirection(value) {
  direction = value;
  $('inButton').classList.toggle('selected', value === 'in');
  $('outButton').classList.toggle('selected', value === 'out');
}
$('inButton').onclick = () => setDirection('in');
$('outButton').onclick = () => setDirection('out');

function message(text, error = false) {
  const el = $('message');
  el.textContent = text;
  el.classList.toggle('error', error);
  el.hidden = false;
}
function statusHint() {
  const barcode = $('barcode').value.trim();
  const found = beacons.get(barcode);
  $('knownStatus').hidden = !barcode;
  $('knownStatus').textContent = !barcode ? '' : found ? `Existing beacon · currently ${found.direction.toUpperCase()} · last seen at ${found.venue}` : 'New beacon · no previous scan found';
}
$('barcode').addEventListener('input', statusHint);

async function load() {
  const response = await fetch('/api/scans');
  const data = await response.json();
  beacons = new Map(data.beacons.map(b => [b.barcode, b]));
  $('total').textContent = data.beacons.length;
  $('inCount').textContent = data.beacons.filter(b => b.direction === 'in').length;
  $('outCount').textContent = data.beacons.filter(b => b.direction === 'out').length;
  $('moveCount').textContent = data.movement_count;
  const body = $('scanRows');
  body.replaceChildren();
  if (!data.scans.length) {
    const row = body.insertRow(); const cell = row.insertCell(); cell.colSpan = 5; cell.className = 'empty'; cell.textContent = 'No scans yet. Scan your first beacon to begin.';
  }
  for (const scan of data.scans.slice(0, 30)) {
    const row = body.insertRow();
    row.insertCell().textContent = scan.barcode;
    const badge = document.createElement('span'); badge.className = `badge ${scan.direction}`; badge.textContent = scan.direction.toUpperCase(); row.insertCell().append(badge);
    row.insertCell().textContent = scan.venue;
    row.insertCell().textContent = scan.reason;
    row.insertCell().textContent = new Date(scan.scanned_at).toLocaleString();
  }
  statusHint();
}

$('scanForm').addEventListener('submit', async event => {
  event.preventDefault();
  const barcode = $('barcode').value.trim();
  const venue = $('venue').value.trim();
  const reason = $('reason').value.trim();
  if (!barcode || !venue || !reason) return message('Fill in venue, reason, and barcode.', true);
  try {
    const response = await fetch('/api/scans', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({barcode, venue, reason, direction})});
    const data = await response.json();
    if (!response.ok) return message(data.error || 'Could not save scan.', true);
    message(`${barcode} recorded as ${direction.toUpperCase()}. Ready for the next beacon.`);
    $('barcode').value = '';
    await load();
    $('barcode').focus();
  } catch { message('Could not reach the app server.', true); }
});

async function stopCamera() {
  const activeScanner = scanner;
  scanner = null;
  scanning = false;
  try {
    if (activeScanner) {
      if (activeScanner.isScanning) await activeScanner.stop();
      activeScanner.clear();
    }
  } catch {
    message('Could not stop the camera cleanly. Reload the page if it stays active.', true);
  } finally {
    $('reader').hidden = true;
    $('cameraButton').textContent = '▣   Use camera to scan';
  }
}
$('cameraButton').onclick = async () => {
  if (scanner) return stopCamera();
  if (typeof Html5Qrcode === 'undefined') return message('The camera scanner could not be loaded. Check your internet connection, or use a USB/Bluetooth scanner or enter the barcode.', true);
  try {
    const formats = Html5QrcodeSupportedFormats;
    scanner = new Html5Qrcode('reader', {
      formatsToSupport: [
        formats.CODE_128,
        formats.CODE_39,
        formats.CODE_93,
        formats.EAN_13,
        formats.EAN_8,
        formats.UPC_A,
        formats.UPC_E,
        formats.ITF,
        formats.QR_CODE
      ],
      verbose: false
    });
    const activeScanner = scanner;
    $('reader').hidden = false;
    $('cameraButton').textContent = '■   Stop camera';
    scanning = true;
    await activeScanner.start(
      { facingMode: 'environment' },
      {
        fps: 10,
        qrbox: (width, height) => ({
          width: Math.min(Math.floor(width * 0.9), 500),
          height: Math.min(Math.floor(height * 0.35), 180)
        })
      },
      async decodedText => {
        if (!scanning) return;
        $('barcode').value = decodedText.trim();
        statusHint();
        await stopCamera();
        $('scanForm').requestSubmit();
      },
      () => {}
    );
  } catch {
    await stopCamera();
    message('Camera unavailable. Allow camera access and try again, or use a barcode scanner.', true);
  }
};
load().catch(() => message('Could not load inventory.', true));
