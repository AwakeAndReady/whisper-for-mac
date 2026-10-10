// Reproducible vector artwork. No SF Symbol assets or generated bitmap artwork.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.WHISPER_SHARP_PATH || 'sharp');
const output = __dirname;

const blue = '#1670E8';
const graphite = '#596675';
const markScale = 1.3;
const markPaths = [
  'M 246 472 V 552',
  'M 302 414 V 610',
  'M 358 350 V 674',
  'M 420 386 V 410 Q 420 432 442 432 H 768',
  'M 420 482 V 490 Q 420 512 442 512 H 728',
  'M 420 638 V 614 Q 420 592 442 592 H 684',
];

function iconSVG(twoTone) {
  const ink = twoTone ? 'url(#ink)' : blue;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>Whisper for Mac — Klang zu Text, ${twoTone ? 'Blau und Graphit' : 'Blau'}</title>
  <desc>Original vector artwork: three vertical sound bars and three curved strokes that become horizontal text lines, on a light rounded tile.</desc>
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="0.55" stop-color="#F7F9FC"/>
      <stop offset="1" stop-color="#E7EDF4"/>
    </linearGradient>
    <linearGradient id="ink" gradientUnits="userSpaceOnUse" x1="438" y1="512" x2="558" y2="512">
      <stop offset="0" stop-color="${blue}"/>
      <stop offset="1" stop-color="${graphite}"/>
    </linearGradient>
    <filter id="shadow" x="-15%" y="-15%" width="130%" height="140%">
      <feGaussianBlur stdDeviation="12"/>
    </filter>
  </defs>
  <rect x="56" y="74" width="912" height="912" rx="206" fill="#203249" opacity="0.14" filter="url(#shadow)"/>
  <rect x="56" y="56" width="912" height="912" rx="206" fill="url(#tile)" stroke="#CBD4DF" stroke-width="2"/>
  <rect x="60" y="60" width="904" height="904" rx="202" fill="none" stroke="#FFFFFF" stroke-width="3" opacity="0.8"/>
  <g transform="translate(512 512) scale(${markScale}) translate(-512 -512)" fill="none" stroke="${ink}" stroke-width="40" stroke-linecap="round" stroke-linejoin="round">
    ${markPaths.map(d => `<path d="${d}"/>`).join('\n    ')}
  </g>
</svg>\n`;
}

(async () => {
  const variants = [
    { name: 'sound-to-text-blue', title: 'A · Durchgehend blau', detail: 'Klang und Text als ein gemeinsames Zeichen.', tone: false },
    { name: 'sound-to-text-blue-graphite', title: 'B · Blau und Graphit', detail: 'Blaue Klangform, graue Textlinien.', tone: true },
  ];
  const composites = [];
  for (let i = 0; i < variants.length; i++) {
    const variant = variants[i];
    const svg = iconSVG(variant.tone);
    await fs.writeFile(path.join(output, variant.name + '.svg'), svg);
    for (const size of [1024, 320, 128, 64, 32, 16]) {
      const name = `${variant.name}-${size}.png`;
      await sharp(Buffer.from(svg)).resize(size, size).png().toFile(path.join(output, name));
    }
    const x = 30 + 620 * i;
    composites.push({ input: path.join(output, `${variant.name}-320.png`), left: x + 134, top: 210 });
    const positions = [{ size: 128, x: 76, y: 570 }, { size: 64, x: 260, y: 602 }, { size: 32, x: 388, y: 618 }, { size: 16, x: 500, y: 626 }];
    for (const p of positions) composites.push({ input: path.join(output, `${variant.name}-${p.size}.png`), left: x + p.x, top: p.y });
  }
  const panelSVG = `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="810">
    <rect width="1280" height="810" fill="#F0F2F5"/>
    <g font-family="Helvetica, Arial, sans-serif">
      <text x="42" y="54" font-size="30" font-weight="700" fill="#1E2936">Whisper for Mac · Klang zu Text</text>
      <text x="42" y="85" font-size="17" fill="#667180">Vergrößertes Zeichen · zwei Farbvarianten</text>
      ${variants.map((v, i) => `<rect x="${30 + 620 * i}" y="118" width="600" height="627" rx="22" fill="white"/>
      <text x="${56 + 620 * i}" y="160" font-size="22" font-weight="700" fill="#24303D">${v.title}</text>
      <text x="${56 + 620 * i}" y="188" font-size="16" fill="#667180">${v.detail}</text>
      ${[{s:128,x:140},{s:64,x:292},{s:32,x:404},{s:16,x:508}].map(p => `<text x="${30 + 620 * i + p.x}" y="722" text-anchor="middle" font-size="14" fill="#667180">${p.s} px</text>`).join('')}`).join('')}
      <text x="42" y="782" font-size="14" fill="#667180">Eigenständig gezeichnet · SVG-Quellen und PNG-Exporte</text>
    </g>
  </svg>`;
  await sharp(Buffer.from(panelSVG)).composite(composites).png().toFile(path.join(output, 'comparison.png'));
  await fs.copyFile(path.join(output, 'comparison.png'), path.join(output, 'comparison-larger.png'));
  console.log('Created two SVG masters, PNG sizes 1024/320/128/64/32/16, and comparison.png');
})();
