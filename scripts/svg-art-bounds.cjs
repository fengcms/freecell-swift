// Development helper: detect standalone SVG element bounds using alpha pixels.
const sharp=require(process.env.SHARP_MODULE || 'sharp');
(async()=>{
 const bounds=[];
 for(const file of process.argv.slice(2)) {
  const {data,info}=await sharp(file,{density:72}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let minX=info.width,minY=info.height,maxX=-1,maxY=-1;
  for(let y=0;y<info.height;y++) for(let x=0;x<info.width;x++) {
   if(data[(y*info.width+x)*info.channels+info.channels-1]>16) {
    minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);
   }
  }
  bounds.push(maxX<0?null:[minX,minY,maxX,maxY]);
 }
 console.log(JSON.stringify(bounds));
})().catch(e=>{console.error(e);process.exitCode=1;});
