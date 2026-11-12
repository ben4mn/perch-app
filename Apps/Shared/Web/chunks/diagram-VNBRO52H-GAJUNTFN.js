import{a as T}from"./chunk-CPSK4XWH.js";import{a as D}from"./chunk-TQFMI7OV.js";import{a as A}from"./chunk-P3UUDXS6.js";import"./chunk-R2ORIOP6.js";import"./chunk-CCOXU2DK.js";import"./chunk-YYO3MX2V.js";import"./chunk-G2FU5M7J.js";import"./chunk-UHBSQM7R.js";import"./chunk-P6VKWI6B.js";import"./chunk-DUUDW3Q3.js";import"./chunk-WIFXJHLY.js";import"./chunk-P254TWOB.js";import{C as v}from"./chunk-2T22AEZM.js";import"./chunk-XMWHA2C6.js";import"./chunk-2OTEAYCY.js";import{C as $,N as y,R as w,S as B,T as S,U as F,V as z,W as P,X as W,g as n,i as m,u as C}from"./chunk-ENOKA4ER.js";import"./chunk-WTEJOZNX.js";import"./chunk-G3FHMJCN.js";import"./chunk-YEHCSWIG.js";var E={packet:[]},x=structuredClone(E),L=C.packet,Y=n(()=>{let t=v({...L,...$().packet});return t.showBits&&(t.paddingY+=10),t},"getConfig"),I=n(()=>x.packet,"getPacket"),M=n(t=>{t.length>0&&x.packet.push(t)},"pushWord"),O=n(()=>{w(),x=structuredClone(E)},"clear"),h={pushWord:M,getPacket:I,getConfig:Y,clear:O,setAccTitle:B,getAccTitle:S,setDiagramTitle:P,getDiagramTitle:W,getAccDescription:z,setAccDescription:F},G=1e4,H=n(t=>{D(t,h);let e=-1,o=[],i=1,{bitsPerRow:s}=h.getConfig();for(let{start:a,end:r,label:p}of t.blocks){if(r&&r<a)throw new Error(`Packet block ${a} - ${r} is invalid. End must be greater than start.`);if(a!==e+1)throw new Error(`Packet block ${a} - ${r??a} is not contiguous. It should start from ${e+1}.`);for(e=r??a,m.debug(`Packet block ${a} - ${e} with label ${p}`);o.length<=s+1&&h.getPacket().length<G;){let[b,c]=K({start:a,end:r,label:p},i,s);if(o.push(b),b.end+1===i*s&&(h.pushWord(o),o=[],i++),!c)break;({start:a,end:r,label:p}=c)}}h.pushWord(o)},"populate"),K=n((t,e,o)=>{if(t.end===void 0&&(t.end=t.start),t.start>t.end)throw new Error(`Block start ${t.start} is greater than block end ${t.end}.`);return t.end+1<=e*o?[t,void 0]:[{start:t.start,end:e*o-1,label:t.label},{start:e*o,end:t.end,label:t.label}]},"getNextFittingBlock"),R={parse:n(async t=>{let e=await A("packet",t);m.debug(e),H(e)},"parse")},U=n((t,e,o,i)=>{let s=i.db,a=s.getConfig(),{rowHeight:r,paddingY:p,bitWidth:b,bitsPerRow:c}=a,u=s.getPacket(),l=s.getDiagramTitle(),g=r+p,d=g*(u.length+1)-(l?0:r),k=b*c+2,f=T(e);f.attr("viewbox",`0 0 ${k} ${d}`),y(f,d,k,a.useMaxWidth);for(let[_,N]of u.entries())X(f,N,_,a);f.append("text").text(l).attr("x",k/2).attr("y",d-g/2).attr("dominant-baseline","middle").attr("text-anchor","middle").attr("class","packetTitle")},"draw"),X=n((t,e,o,{rowHeight:i,paddingX:s,paddingY:a,bitWidth:r,bitsPerRow:p,showBits:b})=>{let c=t.append("g"),u=o*(i+a)+a;for(let l of e){let g=l.start%p*r+1,d=(l.end-l.start+1)*r-s;if(c.append("rect").attr("x",g).attr("y",u).attr("width",d).attr("height",i).attr("class","packetBlock"),c.append("text").attr("x",g+d/2).attr("y",u+i/2).attr("class","packetLabel").attr("dominant-baseline","middle").attr("text-anchor","middle").text(l.label),!b)continue;let k=l.end===l.start,f=u-2;c.append("text").attr("x",g+(k?d/2:0)).attr("y",f).attr("class","packetByte start").attr("dominant-baseline","auto").attr("text-anchor",k?"middle":"start").text(l.start),k||c.append("text").attr("x",g+d).attr("y",f).attr("class","packetByte end").attr("dominant-baseline","auto").attr("text-anchor","end").text(l.end)}},"drawWord"),j={draw:U},q={byteFontSize:"10px",startByteColor:"black",endByteColor:"black",labelColor:"black",labelFontSize:"12px",titleColor:"black",titleFontSize:"14px",blockStrokeColor:"black",blockStrokeWidth:"1",blockFillColor:"#efefef"},J=n(({packet:t}={})=>{let e=v(q,t);return`
	.packetByte {
		font-size: ${e.byteFontSize};
	}
	.packetByte.start {
		fill: ${e.startByteColor};
	}
	.packetByte.end {
		fill: ${e.endByteColor};
	}
	.packetLabel {
		fill: ${e.labelColor};
		font-size: ${e.labelFontSize};
	}
	.packetTitle {
		fill: ${e.titleColor};
		font-size: ${e.titleFontSize};
	}
	.packetBlock {
		stroke: ${e.blockStrokeColor};
		stroke-width: ${e.blockStrokeWidth};
		fill: ${e.blockFillColor};
	}
	`},"styles"),at={parser:R,db:h,renderer:j,styles:J};export{at as diagram};
