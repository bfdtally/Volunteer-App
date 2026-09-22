export type BrandPalette={primary:string;secondary:string};
const hex=(n:number)=>n.toString(16).padStart(2,'0');
export const rgbToHex=(r:number,g:number,b:number)=>`#${hex(r)}${hex(g)}${hex(b)}`;
export async function extractBrandPalette(file:File):Promise<BrandPalette>{
 const bitmap=await createImageBitmap(file);const canvas=document.createElement('canvas');canvas.width=80;canvas.height=80;
 const context=canvas.getContext('2d',{willReadFrequently:true});if(!context)return{primary:'#163a5f',secondary:'#ef7b45'};
 context.drawImage(bitmap,0,0,80,80);const pixels=context.getImageData(0,0,80,80).data;const colors=new Map<string,{count:number;r:number;g:number;b:number}>();
 for(let i=0;i<pixels.length;i+=16){const r=pixels[i],g=pixels[i+1],b=pixels[i+2],a=pixels[i+3];if(a<180)continue;const max=Math.max(r,g,b),min=Math.min(r,g,b);if(max>238||max<35||max-min<24)continue;const qr=Math.round(r/32)*32,qg=Math.round(g/32)*32,qb=Math.round(b/32)*32,key=`${qr},${qg},${qb}`;const item=colors.get(key)||{count:0,r:qr,g:qg,b:qb};item.count++;colors.set(key,item)}
 const ranked=[...colors.values()].sort((a,b)=>b.count-a.count);const first=ranked[0]||{r:22,g:58,b:95};const second=ranked.find(c=>Math.abs(c.r-first.r)+Math.abs(c.g-first.g)+Math.abs(c.b-first.b)>150)||ranked[1]||{r:239,g:123,b:69};
 return{primary:rgbToHex(Math.min(first.r,255),Math.min(first.g,255),Math.min(first.b,255)),secondary:rgbToHex(Math.min(second.r,255),Math.min(second.g,255),Math.min(second.b,255))};
}
