// Development tool only: npm install --no-save sharp, then node scripts/generate-cards.cjs.
// SHARP_MODULE may point to an existing sharp installation. No network access is used.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'App/CardSources/Adjusted');
const output = path.join(root, 'Sources/FreeCellApp/Resources/Cards');
const suits = ['clubs', 'diamonds', 'hearts', 'spades'];
const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
(async () => {
  await fs.mkdir(output, { recursive: true });
  const cards = [];
  const tiles = [];
  for (let s = 0; s < suits.length; s++) {
    for (let r = 0; r < ranks.length; r++) {
      const id = s * 13 + r + 1;
      const svg = `${ranks[r]}${'CDHS'[s]}.svg`;
      const png = await sharp(path.join(source, svg), { density: 300 })
        .resize(528, 768, { fit: 'fill' }).png().toBuffer();
      await fs.writeFile(path.join(output, `${id}.png`), png);
      const metadata = await sharp(png).metadata();
      if (metadata.width !== 528 || metadata.height !== 768) throw new Error(`Invalid card ${id}`);
      cards.push({ id, suit: suits[s], rank: r + 1, file: `${id}.png`, sourceFile: svg });
      tiles.push({ input: await sharp(png).resize(106, 154).flatten({ background: '#ffffff' }).toBuffer(), left: r * 116 + 5, top: s * 164 + 5 });
    }
  }
  await sharp({ create: { width: 1508, height: 656, channels: 3, background: '#185b40' } })
    .composite(tiles).jpeg({ quality: 92 }).toFile(path.join(root, 'docs/previews/deck-contact-sheet.jpg'));
  await fs.writeFile(path.join(root, 'docs/card-resources.json'), JSON.stringify({
    source: 'https://github.com/notpeter/Vector-Playing-Cards',
    sourceCommit: '72cb5b288ed61251ef344e369446687cd51281a4',
    author: 'Byron Knoll; Vector-Playing-Cards contributors',
    license: 'Public Domain; optional WTFPL in jurisdictions that do not recognize public domain',
    style: 'Warm ivory radial gradients; bold inset indices; A artwork 90%, number artwork 88%, face artwork 110%, centered, without portrait outline',
    dimensions: [528, 768], displayAspectRatio: [264, 384], cards
  }, null, 2) + '\n');
  console.log(`Generated and decoded ${cards.length} cards, manifest and contact sheet.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
