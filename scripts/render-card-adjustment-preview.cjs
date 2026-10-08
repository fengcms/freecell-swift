// node scripts/render-card-adjustment-preview.cjs (requires sharp; see generate-cards.cjs).
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const path = require('node:path');
const fs = require('node:fs/promises');
const root = path.resolve(__dirname,'..');
(async()=>{
 const names=['AS','10D','JC','QH','KS'];
 const tiles=[];
 for(let i=0;i<names.length;i++) {
  for(let variant=0;variant<2;variant++) {
   const file=path.join(root,'App/CardSources',variant?'PreviewAdjusted':'cards-svg',names[i]+'.svg');
   const png=await sharp(file,{density:300}).resize(528,768).png().toBuffer();
   if(variant) await fs.writeFile(path.join(root,'docs/previews/card-adjustments',names[i]+'.png'),png);
   for(let size=0;size<2;size++) {
    const width=size?90:165;
    tiles.push({input:await sharp(png).resize({width}).toBuffer(),left:90+i*185,top:48+variant*265+size*560});
   }
  }
 }
 const label=Buffer.from(`<svg width="1040" height="1030" xmlns="http://www.w3.org/2000/svg"><g fill="white" font-family="Arial" font-size="16"><text x="16" y="30">Original / Adjusted · large and game-size previews</text><text x="10" y="130">Before</text><text x="10" y="400">After</text><text x="10" y="660">Before</text><text x="10" y="930">After</text></g></svg>`);
 await sharp({create:{width:1040,height:1030,channels:3,background:'#185b40'}}).composite([...tiles,{input:label,left:0,top:0}]).png().toFile(path.join(root,'docs/previews/card-adjustment-comparison.png'));
 console.log('Rendered comparison and five full-size previews.');
})().catch(e=>{console.error(e);process.exitCode=1;});
