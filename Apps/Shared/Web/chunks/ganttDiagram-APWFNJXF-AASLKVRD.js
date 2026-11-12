import{a as ge,b as pe,f as ve,h as It,i as Lt,j as Ft,k as Yt,l as Wt,m as be,n as Te,o as xe,p as we,q as _e,r as De,s as Se,t as Vt,u as Ot,x as Ce,y as Ee}from"./chunk-YOC5A7DK.js";import{D as Me}from"./chunk-2T22AEZM.js";import{a as $e}from"./chunk-XMWHA2C6.js";import"./chunk-2OTEAYCY.js";import{M as ce,N as le,R as ue,S as de,T as fe,U as he,V as ke,W as me,X as ye,Y as it,a as oe,da as mt,g as c,i as kt}from"./chunk-ENOKA4ER.js";import"./chunk-WTEJOZNX.js";import"./chunk-G3FHMJCN.js";import{a as At,d as dt}from"./chunk-YEHCSWIG.js";var Ye=At((Rt,Nt)=>{(function(t,e){typeof Rt=="object"&&typeof Nt<"u"?Nt.exports=e():typeof define=="function"&&define.amd?define(e):(t=typeof globalThis<"u"?globalThis:t||self).dayjs_plugin_isoWeek=e()})(Rt,function(){"use strict";var t="day";return function(e,i,s){var n=function(S){return S.add(4-S.isoWeekday(),t)},d=i.prototype;d.isoWeekYear=function(){return n(this).year()},d.isoWeek=function(S){if(!this.$utils().u(S))return this.add(7*(S-this.isoWeek()),t);var T,E,C,W,M=n(this),w=(T=this.isoWeekYear(),E=this.$u,C=(E?s.utc:s)().year(T).startOf("year"),W=4-C.isoWeekday(),C.isoWeekday()>4&&(W+=7),C.add(W,t));return M.diff(w,"week")+1},d.isoWeekday=function(S){return this.$utils().u(S)?this.day()||7:this.day(this.day()%7?S:S-7)};var h=d.startOf;d.startOf=function(S,T){var E=this.$utils(),C=!!E.u(T)||T;return E.p(S)==="isoweek"?C?this.date(this.date()-(this.isoWeekday()-1)).startOf("day"):this.date(this.date()-1-(this.isoWeekday()-1)+7).endOf("day"):h.bind(this)(S,T)}}})});var We=At((Bt,jt)=>{(function(t,e){typeof Bt=="object"&&typeof jt<"u"?jt.exports=e():typeof define=="function"&&define.amd?define(e):(t=typeof globalThis<"u"?globalThis:t||self).dayjs_plugin_customParseFormat=e()})(Bt,function(){"use strict";var t={LTS:"h:mm:ss A",LT:"h:mm A",L:"MM/DD/YYYY",LL:"MMMM D, YYYY",LLL:"MMMM D, YYYY h:mm A",LLLL:"dddd, MMMM D, YYYY h:mm A"},e=/(\[[^[]*\])|([-_:/.,()\s]+)|(A|a|Q|YYYY|YY?|ww?|MM?M?M?|Do|DD?|hh?|HH?|mm?|ss?|S{1,3}|z|ZZ?)/g,i=/\d/,s=/\d\d/,n=/\d\d?/,d=/\d*[^-_:/,()\s\d]+/,h={},S=function(g){return(g=+g)+(g>68?1900:2e3)},T=function(g){return function(y){this[g]=+y}},E=[/[+-]\d\d:?(\d\d)?|Z/,function(g){(this.zone||(this.zone={})).offset=function(y){if(!y||y==="Z")return 0;var I=y.match(/([+-]|\d\d)/g),L=60*I[1]+(+I[2]||0);return L===0?0:I[0]==="+"?-L:L}(g)}],C=function(g){var y=h[g];return y&&(y.indexOf?y:y.s.concat(y.f))},W=function(g,y){var I,L=h.meridiem;if(L){for(var R=1;R<=24;R+=1)if(g.indexOf(L(R,0,y))>-1){I=R>12;break}}else I=g===(y?"pm":"PM");return I},M={A:[d,function(g){this.afternoon=W(g,!1)}],a:[d,function(g){this.afternoon=W(g,!0)}],Q:[i,function(g){this.month=3*(g-1)+1}],S:[i,function(g){this.milliseconds=100*+g}],SS:[s,function(g){this.milliseconds=10*+g}],SSS:[/\d{3}/,function(g){this.milliseconds=+g}],s:[n,T("seconds")],ss:[n,T("seconds")],m:[n,T("minutes")],mm:[n,T("minutes")],H:[n,T("hours")],h:[n,T("hours")],HH:[n,T("hours")],hh:[n,T("hours")],D:[n,T("day")],DD:[s,T("day")],Do:[d,function(g){var y=h.ordinal,I=g.match(/\d+/);if(this.day=I[0],y)for(var L=1;L<=31;L+=1)y(L).replace(/\[|\]/g,"")===g&&(this.day=L)}],w:[n,T("week")],ww:[s,T("week")],M:[n,T("month")],MM:[s,T("month")],MMM:[d,function(g){var y=C("months"),I=(C("monthsShort")||y.map(function(L){return L.slice(0,3)})).indexOf(g)+1;if(I<1)throw new Error;this.month=I%12||I}],MMMM:[d,function(g){var y=C("months").indexOf(g)+1;if(y<1)throw new Error;this.month=y%12||y}],Y:[/[+-]?\d+/,T("year")],YY:[s,function(g){this.year=S(g)}],YYYY:[/\d{4}/,T("year")],Z:E,ZZ:E};function w(g){var y,I;y=g,I=h&&h.formats;for(var L=(g=y.replace(/(\[[^\]]+])|(LTS?|l{1,4}|L{1,4})/g,function(p,x,v){var b=v&&v.toUpperCase();return x||I[v]||t[v]||I[b].replace(/(\[[^\]]+])|(MMMM|MM|DD|dddd)/g,function(m,D,o){return D||o.slice(1)})})).match(e),R=L.length,N=0;N<R;N+=1){var X=L[N],B=M[X],P=B&&B[0],V=B&&B[1];L[N]=V?{regex:P,parser:V}:X.replace(/^\[|\]$/g,"")}return function(p){for(var x={},v=0,b=0;v<R;v+=1){var m=L[v];if(typeof m=="string")b+=m.length;else{var D=m.regex,o=m.parser,l=p.slice(b),k=D.exec(l)[0];o.call(x,k),p=p.replace(k,"")}}return function(f){var _=f.afternoon;if(_!==void 0){var r=f.hours;_?r<12&&(f.hours+=12):r===12&&(f.hours=0),delete f.afternoon}}(x),x}}return function(g,y,I){I.p.customParseFormat=!0,g&&g.parseTwoDigitYear&&(S=g.parseTwoDigitYear);var L=y.prototype,R=L.parse;L.parse=function(N){var X=N.date,B=N.utc,P=N.args;this.$u=B;var V=P[1];if(typeof V=="string"){var p=P[2]===!0,x=P[3]===!0,v=p||x,b=P[2];x&&(b=P[2]),h=this.$locale(),!p&&b&&(h=I.Ls[b]),this.$d=function(l,k,f,_){try{if(["x","X"].indexOf(k)>-1)return new Date((k==="X"?1e3:1)*l);var r=w(k)(l),u=r.year,a=r.month,Y=r.day,A=r.hours,F=r.minutes,G=r.seconds,O=r.milliseconds,st=r.zone,z=r.week,Q=new Date,et=Y||(u||a?1:Q.getDate()),rt=u||Q.getFullYear(),ot=0;u&&!a||(ot=a>0?a-1:Q.getMonth());var ct,lt=A||0,j=F||0,nt=G||0,K=O||0;return st?new Date(Date.UTC(rt,ot,et,lt,j,nt,K+60*st.offset*1e3)):f?new Date(Date.UTC(rt,ot,et,lt,j,nt,K)):(ct=new Date(rt,ot,et,lt,j,nt,K),z&&(ct=_(ct).week(z).toDate()),ct)}catch{return new Date("")}}(X,V,B,I),this.init(),b&&b!==!0&&(this.$L=this.locale(b).$L),v&&X!=this.format(V)&&(this.$d=new Date("")),h={}}else if(V instanceof Array)for(var m=V.length,D=1;D<=m;D+=1){P[1]=V[D-1];var o=I.apply(this,P);if(o.isValid()){this.$d=o.$d,this.$L=o.$L,this.init();break}D===m&&(this.$d=new Date(""))}else R.call(this,N)}}})});var Ve=At((Ht,Gt)=>{(function(t,e){typeof Ht=="object"&&typeof Gt<"u"?Gt.exports=e():typeof define=="function"&&define.amd?define(e):(t=typeof globalThis<"u"?globalThis:t||self).dayjs_plugin_advancedFormat=e()})(Ht,function(){"use strict";return function(t,e){var i=e.prototype,s=i.format;i.format=function(n){var d=this,h=this.$locale();if(!this.isValid())return s.bind(this)(n);var S=this.$utils(),T=(n||"YYYY-MM-DDTHH:mm:ssZ").replace(/\[([^\]]+)]|Q|wo|ww|w|WW|W|zzz|z|gggg|GGGG|Do|X|x|k{1,2}|S/g,function(E){switch(E){case"Q":return Math.ceil((d.$M+1)/3);case"Do":return h.ordinal(d.$D);case"gggg":return d.weekYear();case"GGGG":return d.isoWeekYear();case"wo":return h.ordinal(d.week(),"W");case"w":case"ww":return S.s(d.week(),E==="w"?1:2,"0");case"W":case"WW":return S.s(d.isoWeek(),E==="W"?1:2,"0");case"k":case"kk":return S.s(String(d.$H===0?24:d.$H),E==="k"?1:2,"0");case"X":return Math.floor(d.$d.getTime()/1e3);case"x":return d.$d.getTime();case"z":return"["+d.offsetName()+"]";case"zzz":return"["+d.offsetName("long")+"]";default:return E}});return s.bind(this)(T)}}})});function Je(t){return t}var xt=1,zt=2,Pt=3,Tt=4,Ae=1e-6;function tr(t){return"translate("+t+",0)"}function er(t){return"translate(0,"+t+")"}function rr(t){return e=>+t(e)}function nr(t,e){return e=Math.max(0,t.bandwidth()-e*2)/2,t.round()&&(e=Math.round(e)),i=>+t(i)+e}function ir(){return!this.__axis}function Ie(t,e){var i=[],s=null,n=null,d=6,h=6,S=3,T=typeof window<"u"&&window.devicePixelRatio>1?0:.5,E=t===xt||t===Tt?-1:1,C=t===Tt||t===zt?"x":"y",W=t===xt||t===Pt?tr:er;function M(w){var g=s??(e.ticks?e.ticks.apply(e,i):e.domain()),y=n??(e.tickFormat?e.tickFormat.apply(e,i):Je),I=Math.max(d,0)+S,L=e.range(),R=+L[0]+T,N=+L[L.length-1]+T,X=(e.bandwidth?nr:rr)(e.copy(),T),B=w.selection?w.selection():w,P=B.selectAll(".domain").data([null]),V=B.selectAll(".tick").data(g,e).order(),p=V.exit(),x=V.enter().append("g").attr("class","tick"),v=V.select("line"),b=V.select("text");P=P.merge(P.enter().insert("path",".tick").attr("class","domain").attr("stroke","currentColor")),V=V.merge(x),v=v.merge(x.append("line").attr("stroke","currentColor").attr(C+"2",E*d)),b=b.merge(x.append("text").attr("fill","currentColor").attr(C,E*I).attr("dy",t===xt?"0em":t===Pt?"0.71em":"0.32em")),w!==B&&(P=P.transition(w),V=V.transition(w),v=v.transition(w),b=b.transition(w),p=p.transition(w).attr("opacity",Ae).attr("transform",function(m){return isFinite(m=X(m))?W(m+T):this.getAttribute("transform")}),x.attr("opacity",Ae).attr("transform",function(m){var D=this.parentNode.__axis;return W((D&&isFinite(D=D(m))?D:X(m))+T)})),p.remove(),P.attr("d",t===Tt||t===zt?h?"M"+E*h+","+R+"H"+T+"V"+N+"H"+E*h:"M"+T+","+R+"V"+N:h?"M"+R+","+E*h+"V"+T+"H"+N+"V"+E*h:"M"+R+","+T+"H"+N),V.attr("opacity",1).attr("transform",function(m){return W(X(m)+T)}),v.attr(C+"2",E*d),b.attr(C,E*I).text(y),B.filter(ir).attr("fill","none").attr("font-size",10).attr("font-family","sans-serif").attr("text-anchor",t===zt?"start":t===Tt?"end":"middle"),B.each(function(){this.__axis=X})}return M.scale=function(w){return arguments.length?(e=w,M):e},M.ticks=function(){return i=Array.from(arguments),M},M.tickArguments=function(w){return arguments.length?(i=w==null?[]:Array.from(w),M):i.slice()},M.tickValues=function(w){return arguments.length?(s=w==null?null:Array.from(w),M):s&&s.slice()},M.tickFormat=function(w){return arguments.length?(n=w,M):n},M.tickSize=function(w){return arguments.length?(d=h=+w,M):d},M.tickSizeInner=function(w){return arguments.length?(d=+w,M):d},M.tickSizeOuter=function(w){return arguments.length?(h=+w,M):h},M.tickPadding=function(w){return arguments.length?(S=+w,M):S},M.offset=function(w){return arguments.length?(T=+w,M):T},M}function Le(t){return Ie(xt,t)}function Fe(t){return Ie(Pt,t)}var Re=dt($e(),1),Z=dt(oe(),1),Ne=dt(Ye(),1),Be=dt(We(),1),je=dt(Ve(),1),Dt=dt(oe(),1);var Xt=function(){var t=c(function(D,o,l,k){for(l=l||{},k=D.length;k--;l[D[k]]=o);return l},"o"),e=[6,8,10,12,13,14,15,16,17,18,20,21,22,23,24,25,26,27,28,29,30,31,33,35,36,38,40],i=[1,26],s=[1,27],n=[1,28],d=[1,29],h=[1,30],S=[1,31],T=[1,32],E=[1,33],C=[1,34],W=[1,9],M=[1,10],w=[1,11],g=[1,12],y=[1,13],I=[1,14],L=[1,15],R=[1,16],N=[1,19],X=[1,20],B=[1,21],P=[1,22],V=[1,23],p=[1,25],x=[1,35],v={trace:c(function(){},"trace"),yy:{},symbols_:{error:2,start:3,gantt:4,document:5,EOF:6,line:7,SPACE:8,statement:9,NL:10,weekday:11,weekday_monday:12,weekday_tuesday:13,weekday_wednesday:14,weekday_thursday:15,weekday_friday:16,weekday_saturday:17,weekday_sunday:18,weekend:19,weekend_friday:20,weekend_saturday:21,dateFormat:22,inclusiveEndDates:23,topAxis:24,axisFormat:25,tickInterval:26,excludes:27,includes:28,todayMarker:29,title:30,acc_title:31,acc_title_value:32,acc_descr:33,acc_descr_value:34,acc_descr_multiline_value:35,section:36,clickStatement:37,taskTxt:38,taskData:39,click:40,callbackname:41,callbackargs:42,href:43,clickStatementDebug:44,$accept:0,$end:1},terminals_:{2:"error",4:"gantt",6:"EOF",8:"SPACE",10:"NL",12:"weekday_monday",13:"weekday_tuesday",14:"weekday_wednesday",15:"weekday_thursday",16:"weekday_friday",17:"weekday_saturday",18:"weekday_sunday",20:"weekend_friday",21:"weekend_saturday",22:"dateFormat",23:"inclusiveEndDates",24:"topAxis",25:"axisFormat",26:"tickInterval",27:"excludes",28:"includes",29:"todayMarker",30:"title",31:"acc_title",32:"acc_title_value",33:"acc_descr",34:"acc_descr_value",35:"acc_descr_multiline_value",36:"section",38:"taskTxt",39:"taskData",40:"click",41:"callbackname",42:"callbackargs",43:"href"},productions_:[0,[3,3],[5,0],[5,2],[7,2],[7,1],[7,1],[7,1],[11,1],[11,1],[11,1],[11,1],[11,1],[11,1],[11,1],[19,1],[19,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,1],[9,2],[9,2],[9,1],[9,1],[9,1],[9,2],[37,2],[37,3],[37,3],[37,4],[37,3],[37,4],[37,2],[44,2],[44,3],[44,3],[44,4],[44,3],[44,4],[44,2]],performAction:c(function(o,l,k,f,_,r,u){var a=r.length-1;switch(_){case 1:return r[a-1];case 2:this.$=[];break;case 3:r[a-1].push(r[a]),this.$=r[a-1];break;case 4:case 5:this.$=r[a];break;case 6:case 7:this.$=[];break;case 8:f.setWeekday("monday");break;case 9:f.setWeekday("tuesday");break;case 10:f.setWeekday("wednesday");break;case 11:f.setWeekday("thursday");break;case 12:f.setWeekday("friday");break;case 13:f.setWeekday("saturday");break;case 14:f.setWeekday("sunday");break;case 15:f.setWeekend("friday");break;case 16:f.setWeekend("saturday");break;case 17:f.setDateFormat(r[a].substr(11)),this.$=r[a].substr(11);break;case 18:f.enableInclusiveEndDates(),this.$=r[a].substr(18);break;case 19:f.TopAxis(),this.$=r[a].substr(8);break;case 20:f.setAxisFormat(r[a].substr(11)),this.$=r[a].substr(11);break;case 21:f.setTickInterval(r[a].substr(13)),this.$=r[a].substr(13);break;case 22:f.setExcludes(r[a].substr(9)),this.$=r[a].substr(9);break;case 23:f.setIncludes(r[a].substr(9)),this.$=r[a].substr(9);break;case 24:f.setTodayMarker(r[a].substr(12)),this.$=r[a].substr(12);break;case 27:f.setDiagramTitle(r[a].substr(6)),this.$=r[a].substr(6);break;case 28:this.$=r[a].trim(),f.setAccTitle(this.$);break;case 29:case 30:this.$=r[a].trim(),f.setAccDescription(this.$);break;case 31:f.addSection(r[a].substr(8)),this.$=r[a].substr(8);break;case 33:f.addTask(r[a-1],r[a]),this.$="task";break;case 34:this.$=r[a-1],f.setClickEvent(r[a-1],r[a],null);break;case 35:this.$=r[a-2],f.setClickEvent(r[a-2],r[a-1],r[a]);break;case 36:this.$=r[a-2],f.setClickEvent(r[a-2],r[a-1],null),f.setLink(r[a-2],r[a]);break;case 37:this.$=r[a-3],f.setClickEvent(r[a-3],r[a-2],r[a-1]),f.setLink(r[a-3],r[a]);break;case 38:this.$=r[a-2],f.setClickEvent(r[a-2],r[a],null),f.setLink(r[a-2],r[a-1]);break;case 39:this.$=r[a-3],f.setClickEvent(r[a-3],r[a-1],r[a]),f.setLink(r[a-3],r[a-2]);break;case 40:this.$=r[a-1],f.setLink(r[a-1],r[a]);break;case 41:case 47:this.$=r[a-1]+" "+r[a];break;case 42:case 43:case 45:this.$=r[a-2]+" "+r[a-1]+" "+r[a];break;case 44:case 46:this.$=r[a-3]+" "+r[a-2]+" "+r[a-1]+" "+r[a];break}},"anonymous"),table:[{3:1,4:[1,2]},{1:[3]},t(e,[2,2],{5:3}),{6:[1,4],7:5,8:[1,6],9:7,10:[1,8],11:17,12:i,13:s,14:n,15:d,16:h,17:S,18:T,19:18,20:E,21:C,22:W,23:M,24:w,25:g,26:y,27:I,28:L,29:R,30:N,31:X,33:B,35:P,36:V,37:24,38:p,40:x},t(e,[2,7],{1:[2,1]}),t(e,[2,3]),{9:36,11:17,12:i,13:s,14:n,15:d,16:h,17:S,18:T,19:18,20:E,21:C,22:W,23:M,24:w,25:g,26:y,27:I,28:L,29:R,30:N,31:X,33:B,35:P,36:V,37:24,38:p,40:x},t(e,[2,5]),t(e,[2,6]),t(e,[2,17]),t(e,[2,18]),t(e,[2,19]),t(e,[2,20]),t(e,[2,21]),t(e,[2,22]),t(e,[2,23]),t(e,[2,24]),t(e,[2,25]),t(e,[2,26]),t(e,[2,27]),{32:[1,37]},{34:[1,38]},t(e,[2,30]),t(e,[2,31]),t(e,[2,32]),{39:[1,39]},t(e,[2,8]),t(e,[2,9]),t(e,[2,10]),t(e,[2,11]),t(e,[2,12]),t(e,[2,13]),t(e,[2,14]),t(e,[2,15]),t(e,[2,16]),{41:[1,40],43:[1,41]},t(e,[2,4]),t(e,[2,28]),t(e,[2,29]),t(e,[2,33]),t(e,[2,34],{42:[1,42],43:[1,43]}),t(e,[2,40],{41:[1,44]}),t(e,[2,35],{43:[1,45]}),t(e,[2,36]),t(e,[2,38],{42:[1,46]}),t(e,[2,37]),t(e,[2,39])],defaultActions:{},parseError:c(function(o,l){if(l.recoverable)this.trace(o);else{var k=new Error(o);throw k.hash=l,k}},"parseError"),parse:c(function(o){var l=this,k=[0],f=[],_=[null],r=[],u=this.table,a="",Y=0,A=0,F=0,G=2,O=1,st=r.slice.call(arguments,1),z=Object.create(this.lexer),Q={yy:{}};for(var et in this.yy)Object.prototype.hasOwnProperty.call(this.yy,et)&&(Q.yy[et]=this.yy[et]);z.setInput(o,Q.yy),Q.yy.lexer=z,Q.yy.parser=this,typeof z.yylloc>"u"&&(z.yylloc={});var rt=z.yylloc;r.push(rt);var ot=z.options&&z.options.ranges;typeof Q.yy.parseError=="function"?this.parseError=Q.yy.parseError:this.parseError=Object.getPrototypeOf(this).parseError;function ct(U){k.length=k.length-2*U,_.length=_.length-U,r.length=r.length-U}c(ct,"popStack");function lt(){var U;return U=f.pop()||z.lex()||O,typeof U!="number"&&(U instanceof Array&&(f=U,U=f.pop()),U=l.symbols_[U]||U),U}c(lt,"lex");for(var j,nt,K,q,Ur,Et,ut={},vt,J,se,bt;;){if(K=k[k.length-1],this.defaultActions[K]?q=this.defaultActions[K]:((j===null||typeof j>"u")&&(j=lt()),q=u[K]&&u[K][j]),typeof q>"u"||!q.length||!q[0]){var Mt="";bt=[];for(vt in u[K])this.terminals_[vt]&&vt>G&&bt.push("'"+this.terminals_[vt]+"'");z.showPosition?Mt="Parse error on line "+(Y+1)+`:
`+z.showPosition()+`
Expecting `+bt.join(", ")+", got '"+(this.terminals_[j]||j)+"'":Mt="Parse error on line "+(Y+1)+": Unexpected "+(j==O?"end of input":"'"+(this.terminals_[j]||j)+"'"),this.parseError(Mt,{text:z.match,token:this.terminals_[j]||j,line:z.yylineno,loc:rt,expected:bt})}if(q[0]instanceof Array&&q.length>1)throw new Error("Parse Error: multiple actions possible at state: "+K+", token: "+j);switch(q[0]){case 1:k.push(j),_.push(z.yytext),r.push(z.yylloc),k.push(q[1]),j=null,nt?(j=nt,nt=null):(A=z.yyleng,a=z.yytext,Y=z.yylineno,rt=z.yylloc,F>0&&F--);break;case 2:if(J=this.productions_[q[1]][1],ut.$=_[_.length-J],ut._$={first_line:r[r.length-(J||1)].first_line,last_line:r[r.length-1].last_line,first_column:r[r.length-(J||1)].first_column,last_column:r[r.length-1].last_column},ot&&(ut._$.range=[r[r.length-(J||1)].range[0],r[r.length-1].range[1]]),Et=this.performAction.apply(ut,[a,A,Y,Q.yy,q[1],_,r].concat(st)),typeof Et<"u")return Et;J&&(k=k.slice(0,-1*J*2),_=_.slice(0,-1*J),r=r.slice(0,-1*J)),k.push(this.productions_[q[1]][0]),_.push(ut.$),r.push(ut._$),se=u[k[k.length-2]][k[k.length-1]],k.push(se);break;case 3:return!0}}return!0},"parse")},b=function(){var D={EOF:1,parseError:c(function(l,k){if(this.yy.parser)this.yy.parser.parseError(l,k);else throw new Error(l)},"parseError"),setInput:c(function(o,l){return this.yy=l||this.yy||{},this._input=o,this._more=this._backtrack=this.done=!1,this.yylineno=this.yyleng=0,this.yytext=this.matched=this.match="",this.conditionStack=["INITIAL"],this.yylloc={first_line:1,first_column:0,last_line:1,last_column:0},this.options.ranges&&(this.yylloc.range=[0,0]),this.offset=0,this},"setInput"),input:c(function(){var o=this._input[0];this.yytext+=o,this.yyleng++,this.offset++,this.match+=o,this.matched+=o;var l=o.match(/(?:\r\n?|\n).*/g);return l?(this.yylineno++,this.yylloc.last_line++):this.yylloc.last_column++,this.options.ranges&&this.yylloc.range[1]++,this._input=this._input.slice(1),o},"input"),unput:c(function(o){var l=o.length,k=o.split(/(?:\r\n?|\n)/g);this._input=o+this._input,this.yytext=this.yytext.substr(0,this.yytext.length-l),this.offset-=l;var f=this.match.split(/(?:\r\n?|\n)/g);this.match=this.match.substr(0,this.match.length-1),this.matched=this.matched.substr(0,this.matched.length-1),k.length-1&&(this.yylineno-=k.length-1);var _=this.yylloc.range;return this.yylloc={first_line:this.yylloc.first_line,last_line:this.yylineno+1,first_column:this.yylloc.first_column,last_column:k?(k.length===f.length?this.yylloc.first_column:0)+f[f.length-k.length].length-k[0].length:this.yylloc.first_column-l},this.options.ranges&&(this.yylloc.range=[_[0],_[0]+this.yyleng-l]),this.yyleng=this.yytext.length,this},"unput"),more:c(function(){return this._more=!0,this},"more"),reject:c(function(){if(this.options.backtrack_lexer)this._backtrack=!0;else return this.parseError("Lexical error on line "+(this.yylineno+1)+`. You can only invoke reject() in the lexer when the lexer is of the backtracking persuasion (options.backtrack_lexer = true).
`+this.showPosition(),{text:"",token:null,line:this.yylineno});return this},"reject"),less:c(function(o){this.unput(this.match.slice(o))},"less"),pastInput:c(function(){var o=this.matched.substr(0,this.matched.length-this.match.length);return(o.length>20?"...":"")+o.substr(-20).replace(/\n/g,"")},"pastInput"),upcomingInput:c(function(){var o=this.match;return o.length<20&&(o+=this._input.substr(0,20-o.length)),(o.substr(0,20)+(o.length>20?"...":"")).replace(/\n/g,"")},"upcomingInput"),showPosition:c(function(){var o=this.pastInput(),l=new Array(o.length+1).join("-");return o+this.upcomingInput()+`
`+l+"^"},"showPosition"),test_match:c(function(o,l){var k,f,_;if(this.options.backtrack_lexer&&(_={yylineno:this.yylineno,yylloc:{first_line:this.yylloc.first_line,last_line:this.last_line,first_column:this.yylloc.first_column,last_column:this.yylloc.last_column},yytext:this.yytext,match:this.match,matches:this.matches,matched:this.matched,yyleng:this.yyleng,offset:this.offset,_more:this._more,_input:this._input,yy:this.yy,conditionStack:this.conditionStack.slice(0),done:this.done},this.options.ranges&&(_.yylloc.range=this.yylloc.range.slice(0))),f=o[0].match(/(?:\r\n?|\n).*/g),f&&(this.yylineno+=f.length),this.yylloc={first_line:this.yylloc.last_line,last_line:this.yylineno+1,first_column:this.yylloc.last_column,last_column:f?f[f.length-1].length-f[f.length-1].match(/\r?\n?/)[0].length:this.yylloc.last_column+o[0].length},this.yytext+=o[0],this.match+=o[0],this.matches=o,this.yyleng=this.yytext.length,this.options.ranges&&(this.yylloc.range=[this.offset,this.offset+=this.yyleng]),this._more=!1,this._backtrack=!1,this._input=this._input.slice(o[0].length),this.matched+=o[0],k=this.performAction.call(this,this.yy,this,l,this.conditionStack[this.conditionStack.length-1]),this.done&&this._input&&(this.done=!1),k)return k;if(this._backtrack){for(var r in _)this[r]=_[r];return!1}return!1},"test_match"),next:c(function(){if(this.done)return this.EOF;this._input||(this.done=!0);var o,l,k,f;this._more||(this.yytext="",this.match="");for(var _=this._currentRules(),r=0;r<_.length;r++)if(k=this._input.match(this.rules[_[r]]),k&&(!l||k[0].length>l[0].length)){if(l=k,f=r,this.options.backtrack_lexer){if(o=this.test_match(k,_[r]),o!==!1)return o;if(this._backtrack){l=!1;continue}else return!1}else if(!this.options.flex)break}return l?(o=this.test_match(l,_[f]),o!==!1?o:!1):this._input===""?this.EOF:this.parseError("Lexical error on line "+(this.yylineno+1)+`. Unrecognized text.
`+this.showPosition(),{text:"",token:null,line:this.yylineno})},"next"),lex:c(function(){var l=this.next();return l||this.lex()},"lex"),begin:c(function(l){this.conditionStack.push(l)},"begin"),popState:c(function(){var l=this.conditionStack.length-1;return l>0?this.conditionStack.pop():this.conditionStack[0]},"popState"),_currentRules:c(function(){return this.conditionStack.length&&this.conditionStack[this.conditionStack.length-1]?this.conditions[this.conditionStack[this.conditionStack.length-1]].rules:this.conditions.INITIAL.rules},"_currentRules"),topState:c(function(l){return l=this.conditionStack.length-1-Math.abs(l||0),l>=0?this.conditionStack[l]:"INITIAL"},"topState"),pushState:c(function(l){this.begin(l)},"pushState"),stateStackSize:c(function(){return this.conditionStack.length},"stateStackSize"),options:{"case-insensitive":!0},performAction:c(function(l,k,f,_){var r=_;switch(f){case 0:return this.begin("open_directive"),"open_directive";break;case 1:return this.begin("acc_title"),31;break;case 2:return this.popState(),"acc_title_value";break;case 3:return this.begin("acc_descr"),33;break;case 4:return this.popState(),"acc_descr_value";break;case 5:this.begin("acc_descr_multiline");break;case 6:this.popState();break;case 7:return"acc_descr_multiline_value";case 8:break;case 9:break;case 10:break;case 11:return 10;case 12:break;case 13:break;case 14:this.begin("href");break;case 15:this.popState();break;case 16:return 43;case 17:this.begin("callbackname");break;case 18:this.popState();break;case 19:this.popState(),this.begin("callbackargs");break;case 20:return 41;case 21:this.popState();break;case 22:return 42;case 23:this.begin("click");break;case 24:this.popState();break;case 25:return 40;case 26:return 4;case 27:return 22;case 28:return 23;case 29:return 24;case 30:return 25;case 31:return 26;case 32:return 28;case 33:return 27;case 34:return 29;case 35:return 12;case 36:return 13;case 37:return 14;case 38:return 15;case 39:return 16;case 40:return 17;case 41:return 18;case 42:return 20;case 43:return 21;case 44:return"date";case 45:return 30;case 46:return"accDescription";case 47:return 36;case 48:return 38;case 49:return 39;case 50:return":";case 51:return 6;case 52:return"INVALID"}},"anonymous"),rules:[/^(?:%%\{)/i,/^(?:accTitle\s*:\s*)/i,/^(?:(?!\n||)*[^\n]*)/i,/^(?:accDescr\s*:\s*)/i,/^(?:(?!\n||)*[^\n]*)/i,/^(?:accDescr\s*\{\s*)/i,/^(?:[\}])/i,/^(?:[^\}]*)/i,/^(?:%%(?!\{)*[^\n]*)/i,/^(?:[^\}]%%*[^\n]*)/i,/^(?:%%*[^\n]*[\n]*)/i,/^(?:[\n]+)/i,/^(?:\s+)/i,/^(?:%[^\n]*)/i,/^(?:href[\s]+["])/i,/^(?:["])/i,/^(?:[^"]*)/i,/^(?:call[\s]+)/i,/^(?:\([\s]*\))/i,/^(?:\()/i,/^(?:[^(]*)/i,/^(?:\))/i,/^(?:[^)]*)/i,/^(?:click[\s]+)/i,/^(?:[\s\n])/i,/^(?:[^\s\n]*)/i,/^(?:gantt\b)/i,/^(?:dateFormat\s[^#\n;]+)/i,/^(?:inclusiveEndDates\b)/i,/^(?:topAxis\b)/i,/^(?:axisFormat\s[^#\n;]+)/i,/^(?:tickInterval\s[^#\n;]+)/i,/^(?:includes\s[^#\n;]+)/i,/^(?:excludes\s[^#\n;]+)/i,/^(?:todayMarker\s[^\n;]+)/i,/^(?:weekday\s+monday\b)/i,/^(?:weekday\s+tuesday\b)/i,/^(?:weekday\s+wednesday\b)/i,/^(?:weekday\s+thursday\b)/i,/^(?:weekday\s+friday\b)/i,/^(?:weekday\s+saturday\b)/i,/^(?:weekday\s+sunday\b)/i,/^(?:weekend\s+friday\b)/i,/^(?:weekend\s+saturday\b)/i,/^(?:\d\d\d\d-\d\d-\d\d\b)/i,/^(?:title\s[^\n]+)/i,/^(?:accDescription\s[^#\n;]+)/i,/^(?:section\s[^\n]+)/i,/^(?:[^:\n]+)/i,/^(?::[^#\n;]+)/i,/^(?::)/i,/^(?:$)/i,/^(?:.)/i],conditions:{acc_descr_multiline:{rules:[6,7],inclusive:!1},acc_descr:{rules:[4],inclusive:!1},acc_title:{rules:[2],inclusive:!1},callbackargs:{rules:[21,22],inclusive:!1},callbackname:{rules:[18,19,20],inclusive:!1},href:{rules:[15,16],inclusive:!1},click:{rules:[24,25],inclusive:!1},INITIAL:{rules:[0,1,3,5,8,9,10,11,12,13,14,17,23,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52],inclusive:!0}}};return D}();v.lexer=b;function m(){this.yy={}}return c(m,"Parser"),m.prototype=v,v.Parser=m,new m}();Xt.parser=Xt;var ar=Xt;Z.default.extend(Ne.default);Z.default.extend(Be.default);Z.default.extend(je.default);var Oe={friday:5,saturday:6},$="",Qt="",Kt=void 0,$t="",yt=[],gt=[],Jt=new Map,te=[],St=[],ht="",ee="",He=["active","done","crit","milestone"],re=[],pt=!1,ne=!1,ie="sunday",Ct="saturday",qt=0,sr=c(function(){te=[],St=[],ht="",re=[],wt=0,Zt=void 0,_t=void 0,H=[],$="",Qt="",ee="",Kt=void 0,$t="",yt=[],gt=[],pt=!1,ne=!1,qt=0,Jt=new Map,ue(),ie="sunday",Ct="saturday"},"clear"),or=c(function(t){Qt=t},"setAxisFormat"),cr=c(function(){return Qt},"getAxisFormat"),lr=c(function(t){Kt=t},"setTickInterval"),ur=c(function(){return Kt},"getTickInterval"),dr=c(function(t){$t=t},"setTodayMarker"),fr=c(function(){return $t},"getTodayMarker"),hr=c(function(t){$=t},"setDateFormat"),kr=c(function(){pt=!0},"enableInclusiveEndDates"),mr=c(function(){return pt},"endDatesAreInclusive"),yr=c(function(){ne=!0},"enableTopAxis"),gr=c(function(){return ne},"topAxisEnabled"),pr=c(function(t){ee=t},"setDisplayMode"),vr=c(function(){return ee},"getDisplayMode"),br=c(function(){return $},"getDateFormat"),Tr=c(function(t){yt=t.toLowerCase().split(/[\s,]+/)},"setIncludes"),xr=c(function(){return yt},"getIncludes"),wr=c(function(t){gt=t.toLowerCase().split(/[\s,]+/)},"setExcludes"),_r=c(function(){return gt},"getExcludes"),Dr=c(function(){return Jt},"getLinks"),Sr=c(function(t){ht=t,te.push(t)},"addSection"),Cr=c(function(){return te},"getSections"),Er=c(function(){let t=ze(),e=10,i=0;for(;!t&&i<e;)t=ze(),i++;return St=H,St},"getTasks"),Ge=c(function(t,e,i,s){return s.includes(t.format(e.trim()))?!1:i.includes("weekends")&&(t.isoWeekday()===Oe[Ct]||t.isoWeekday()===Oe[Ct]+1)||i.includes(t.format("dddd").toLowerCase())?!0:i.includes(t.format(e.trim()))},"isInvalidDate"),Mr=c(function(t){ie=t},"setWeekday"),Ar=c(function(){return ie},"getWeekday"),Ir=c(function(t){Ct=t},"setWeekend"),Xe=c(function(t,e,i,s){if(!i.length||t.manualEndTime)return;let n;t.startTime instanceof Date?n=(0,Z.default)(t.startTime):n=(0,Z.default)(t.startTime,e,!0),n=n.add(1,"d");let d;t.endTime instanceof Date?d=(0,Z.default)(t.endTime):d=(0,Z.default)(t.endTime,e,!0);let[h,S]=Lr(n,d,e,i,s);t.endTime=h.toDate(),t.renderEndTime=S},"checkTaskDates"),Lr=c(function(t,e,i,s,n){let d=!1,h=null;for(;t<=e;)d||(h=e.toDate()),d=Ge(t,i,s,n),d&&(e=e.add(1,"d")),t=t.add(1,"d");return[e,h]},"fixTaskDates"),Ut=c(function(t,e,i){i=i.trim();let n=/^after\s+(?<ids>[\d\w- ]+)/.exec(i);if(n!==null){let h=null;for(let T of n.groups.ids.split(" ")){let E=at(T);E!==void 0&&(!h||E.endTime>h.endTime)&&(h=E)}if(h)return h.endTime;let S=new Date;return S.setHours(0,0,0,0),S}let d=(0,Z.default)(i,e.trim(),!0);if(d.isValid())return d.toDate();{kt.debug("Invalid date:"+i),kt.debug("With date format:"+e.trim());let h=new Date(i);if(h===void 0||isNaN(h.getTime())||h.getFullYear()<-1e4||h.getFullYear()>1e4)throw new Error("Invalid date:"+i);return h}},"getStartDate"),qe=c(function(t){let e=/^(\d+(?:\.\d+)?)([Mdhmswy]|ms)$/.exec(t.trim());return e!==null?[Number.parseFloat(e[1]),e[2]]:[NaN,"ms"]},"parseDuration"),Ue=c(function(t,e,i,s=!1){i=i.trim();let d=/^until\s+(?<ids>[\d\w- ]+)/.exec(i);if(d!==null){let C=null;for(let M of d.groups.ids.split(" ")){let w=at(M);w!==void 0&&(!C||w.startTime<C.startTime)&&(C=w)}if(C)return C.startTime;let W=new Date;return W.setHours(0,0,0,0),W}let h=(0,Z.default)(i,e.trim(),!0);if(h.isValid())return s&&(h=h.add(1,"d")),h.toDate();let S=(0,Z.default)(t),[T,E]=qe(i);if(!Number.isNaN(T)){let C=S.add(T,E);C.isValid()&&(S=C)}return S.toDate()},"getEndDate"),wt=0,ft=c(function(t){return t===void 0?(wt=wt+1,"task"+wt):t},"parseId"),Fr=c(function(t,e){let i;e.substr(0,1)===":"?i=e.substr(1,e.length):i=e;let s=i.split(","),n={};ae(s,n,He);for(let h=0;h<s.length;h++)s[h]=s[h].trim();let d="";switch(s.length){case 1:n.id=ft(),n.startTime=t.endTime,d=s[0];break;case 2:n.id=ft(),n.startTime=Ut(void 0,$,s[0]),d=s[1];break;case 3:n.id=ft(s[0]),n.startTime=Ut(void 0,$,s[1]),d=s[2];break;default:}return d&&(n.endTime=Ue(n.startTime,$,d,pt),n.manualEndTime=(0,Z.default)(d,"YYYY-MM-DD",!0).isValid(),Xe(n,$,gt,yt)),n},"compileData"),Yr=c(function(t,e){let i;e.substr(0,1)===":"?i=e.substr(1,e.length):i=e;let s=i.split(","),n={};ae(s,n,He);for(let d=0;d<s.length;d++)s[d]=s[d].trim();switch(s.length){case 1:n.id=ft(),n.startTime={type:"prevTaskEnd",id:t},n.endTime={data:s[0]};break;case 2:n.id=ft(),n.startTime={type:"getStartDate",startData:s[0]},n.endTime={data:s[1]};break;case 3:n.id=ft(s[0]),n.startTime={type:"getStartDate",startData:s[1]},n.endTime={data:s[2]};break;default:}return n},"parseData"),Zt,_t,H=[],Ze={},Wr=c(function(t,e){let i={section:ht,type:ht,processed:!1,manualEndTime:!1,renderEndTime:null,raw:{data:e},task:t,classes:[]},s=Yr(_t,e);i.raw.startTime=s.startTime,i.raw.endTime=s.endTime,i.id=s.id,i.prevTaskId=_t,i.active=s.active,i.done=s.done,i.crit=s.crit,i.milestone=s.milestone,i.order=qt,qt++;let n=H.push(i);_t=i.id,Ze[i.id]=n-1},"addTask"),at=c(function(t){let e=Ze[t];return H[e]},"findTaskById"),Vr=c(function(t,e){let i={section:ht,type:ht,description:t,task:t,classes:[]},s=Fr(Zt,e);i.startTime=s.startTime,i.endTime=s.endTime,i.id=s.id,i.active=s.active,i.done=s.done,i.crit=s.crit,i.milestone=s.milestone,Zt=i,St.push(i)},"addTaskOrg"),ze=c(function(){let t=c(function(i){let s=H[i],n="";switch(H[i].raw.startTime.type){case"prevTaskEnd":{let d=at(s.prevTaskId);s.startTime=d.endTime;break}case"getStartDate":n=Ut(void 0,$,H[i].raw.startTime.startData),n&&(H[i].startTime=n);break}return H[i].startTime&&(H[i].endTime=Ue(H[i].startTime,$,H[i].raw.endTime.data,pt),H[i].endTime&&(H[i].processed=!0,H[i].manualEndTime=(0,Z.default)(H[i].raw.endTime.data,"YYYY-MM-DD",!0).isValid(),Xe(H[i],$,gt,yt))),H[i].processed},"compileTask"),e=!0;for(let[i,s]of H.entries())t(i),e=e&&s.processed;return e},"compileTasks"),Or=c(function(t,e){let i=e;it().securityLevel!=="loose"&&(i=(0,Re.sanitizeUrl)(e)),t.split(",").forEach(function(s){at(s)!==void 0&&(Ke(s,()=>{window.open(i,"_self")}),Jt.set(s,i))}),Qe(t,"clickable")},"setLink"),Qe=c(function(t,e){t.split(",").forEach(function(i){let s=at(i);s!==void 0&&s.classes.push(e)})},"setClass"),zr=c(function(t,e,i){if(it().securityLevel!=="loose"||e===void 0)return;let s=[];if(typeof i=="string"){s=i.split(/,(?=(?:(?:[^"]*"){2})*[^"]*$)/);for(let d=0;d<s.length;d++){let h=s[d].trim();h.startsWith('"')&&h.endsWith('"')&&(h=h.substr(1,h.length-2)),s[d]=h}}s.length===0&&s.push(t),at(t)!==void 0&&Ke(t,()=>{Me.runFunc(e,...s)})},"setClickFun"),Ke=c(function(t,e){re.push(function(){let i=document.querySelector(`[id="${t}"]`);i!==null&&i.addEventListener("click",function(){e()})},function(){let i=document.querySelector(`[id="${t}-text"]`);i!==null&&i.addEventListener("click",function(){e()})})},"pushFun"),Pr=c(function(t,e,i){t.split(",").forEach(function(s){zr(s,e,i)}),Qe(t,"clickable")},"setClickEvent"),Rr=c(function(t){re.forEach(function(e){e(t)})},"bindFunctions"),Nr={getConfig:c(()=>it().gantt,"getConfig"),clear:sr,setDateFormat:hr,getDateFormat:br,enableInclusiveEndDates:kr,endDatesAreInclusive:mr,enableTopAxis:yr,topAxisEnabled:gr,setAxisFormat:or,getAxisFormat:cr,setTickInterval:lr,getTickInterval:ur,setTodayMarker:dr,getTodayMarker:fr,setAccTitle:de,getAccTitle:fe,setDiagramTitle:me,getDiagramTitle:ye,setDisplayMode:pr,getDisplayMode:vr,setAccDescription:he,getAccDescription:ke,addSection:Sr,getSections:Cr,getTasks:Er,addTask:Wr,findTaskById:at,addTaskOrg:Vr,setIncludes:Tr,getIncludes:xr,setExcludes:wr,getExcludes:_r,setClickEvent:Pr,setLink:Or,getLinks:Dr,bindFunctions:Rr,parseDuration:qe,isInvalidDate:Ge,setWeekday:Mr,getWeekday:Ar,setWeekend:Ir};function ae(t,e,i){let s=!0;for(;s;)s=!1,i.forEach(function(n){let d="^\\s*"+n+"\\s*$",h=new RegExp(d);t[0].match(h)&&(e[n]=!0,t.shift(1),s=!0)})}c(ae,"getTaskTags");var Br=c(function(){kt.debug("Something is calling, setConf, remove the call")},"setConf"),Pe={monday:Te,tuesday:xe,wednesday:we,thursday:_e,friday:De,saturday:Se,sunday:be},jr=c((t,e)=>{let i=[...t].map(()=>-1/0),s=[...t].sort((d,h)=>d.startTime-h.startTime||d.order-h.order),n=0;for(let d of s)for(let h=0;h<i.length;h++)if(d.startTime>=i[h]){i[h]=d.endTime,d.order=h+e,h>n&&(n=h);break}return n},"getMaxIntersections"),tt,Hr=c(function(t,e,i,s){let n=it().gantt,d=it().securityLevel,h;d==="sandbox"&&(h=mt("#i"+e));let S=d==="sandbox"?mt(h.nodes()[0].contentDocument.body):mt("body"),T=d==="sandbox"?h.nodes()[0].contentDocument:document,E=T.getElementById(e);tt=E.parentElement.offsetWidth,tt===void 0&&(tt=1200),n.useWidth!==void 0&&(tt=n.useWidth);let C=s.db.getTasks(),W=[];for(let p of C)W.push(p.type);W=V(W);let M={},w=2*n.topPadding;if(s.db.getDisplayMode()==="compact"||n.displayMode==="compact"){let p={};for(let v of C)p[v.section]===void 0?p[v.section]=[v]:p[v.section].push(v);let x=0;for(let v of Object.keys(p)){let b=jr(p[v],x)+1;x+=b,w+=b*(n.barHeight+n.barGap),M[v]=b}}else{w+=C.length*(n.barHeight+n.barGap);for(let p of W)M[p]=C.filter(x=>x.type===p).length}E.setAttribute("viewBox","0 0 "+tt+" "+w);let g=S.select(`[id="${e}"]`),y=Ee().domain([pe(C,function(p){return p.startTime}),ge(C,function(p){return p.endTime})]).rangeRound([0,tt-n.leftPadding-n.rightPadding]);function I(p,x){let v=p.startTime,b=x.startTime,m=0;return v>b?m=1:v<b&&(m=-1),m}c(I,"taskCompare"),C.sort(I),L(C,tt,w),le(g,w,tt,n.useMaxWidth),g.append("text").text(s.db.getDiagramTitle()).attr("x",tt/2).attr("y",n.titleTopMargin).attr("class","titleText");function L(p,x,v){let b=n.barHeight,m=b+n.barGap,D=n.topPadding,o=n.leftPadding,l=Ce().domain([0,W.length]).range(["#00B9FA","#F95002"]).interpolate(ve);N(m,D,o,x,v,p,s.db.getExcludes(),s.db.getIncludes()),X(o,D,x,v),R(p,m,D,o,b,l,x,v),B(m,D,o,b,l),P(o,D,x,v)}c(L,"makeGantt");function R(p,x,v,b,m,D,o){let k=[...new Set(p.map(u=>u.order))].map(u=>p.find(a=>a.order===u));g.append("g").selectAll("rect").data(k).enter().append("rect").attr("x",0).attr("y",function(u,a){return a=u.order,a*x+v-2}).attr("width",function(){return o-n.rightPadding/2}).attr("height",x).attr("class",function(u){for(let[a,Y]of W.entries())if(u.type===Y)return"section section"+a%n.numberSectionStyles;return"section section0"});let f=g.append("g").selectAll("rect").data(p).enter(),_=s.db.getLinks();if(f.append("rect").attr("id",function(u){return u.id}).attr("rx",3).attr("ry",3).attr("x",function(u){return u.milestone?y(u.startTime)+b+.5*(y(u.endTime)-y(u.startTime))-.5*m:y(u.startTime)+b}).attr("y",function(u,a){return a=u.order,a*x+v}).attr("width",function(u){return u.milestone?m:y(u.renderEndTime||u.endTime)-y(u.startTime)}).attr("height",m).attr("transform-origin",function(u,a){return a=u.order,(y(u.startTime)+b+.5*(y(u.endTime)-y(u.startTime))).toString()+"px "+(a*x+v+.5*m).toString()+"px"}).attr("class",function(u){let a="task",Y="";u.classes.length>0&&(Y=u.classes.join(" "));let A=0;for(let[G,O]of W.entries())u.type===O&&(A=G%n.numberSectionStyles);let F="";return u.active?u.crit?F+=" activeCrit":F=" active":u.done?u.crit?F=" doneCrit":F=" done":u.crit&&(F+=" crit"),F.length===0&&(F=" task"),u.milestone&&(F=" milestone "+F),F+=A,F+=" "+Y,a+F}),f.append("text").attr("id",function(u){return u.id+"-text"}).text(function(u){return u.task}).attr("font-size",n.fontSize).attr("x",function(u){let a=y(u.startTime),Y=y(u.renderEndTime||u.endTime);u.milestone&&(a+=.5*(y(u.endTime)-y(u.startTime))-.5*m),u.milestone&&(Y=a+m);let A=this.getBBox().width;return A>Y-a?Y+A+1.5*n.leftPadding>o?a+b-5:Y+b+5:(Y-a)/2+a+b}).attr("y",function(u,a){return a=u.order,a*x+n.barHeight/2+(n.fontSize/2-2)+v}).attr("text-height",m).attr("class",function(u){let a=y(u.startTime),Y=y(u.endTime);u.milestone&&(Y=a+m);let A=this.getBBox().width,F="";u.classes.length>0&&(F=u.classes.join(" "));let G=0;for(let[st,z]of W.entries())u.type===z&&(G=st%n.numberSectionStyles);let O="";return u.active&&(u.crit?O="activeCritText"+G:O="activeText"+G),u.done?u.crit?O=O+" doneCritText"+G:O=O+" doneText"+G:u.crit&&(O=O+" critText"+G),u.milestone&&(O+=" milestoneText"),A>Y-a?Y+A+1.5*n.leftPadding>o?F+" taskTextOutsideLeft taskTextOutside"+G+" "+O:F+" taskTextOutsideRight taskTextOutside"+G+" "+O+" width-"+A:F+" taskText taskText"+G+" "+O+" width-"+A}),it().securityLevel==="sandbox"){let u;u=mt("#i"+e);let a=u.nodes()[0].contentDocument;f.filter(function(Y){return _.has(Y.id)}).each(function(Y){var A=a.querySelector("#"+Y.id),F=a.querySelector("#"+Y.id+"-text");let G=A.parentNode;var O=a.createElement("a");O.setAttribute("xlink:href",_.get(Y.id)),O.setAttribute("target","_top"),G.appendChild(O),O.appendChild(A),O.appendChild(F)})}}c(R,"drawRects");function N(p,x,v,b,m,D,o,l){if(o.length===0&&l.length===0)return;let k,f;for(let{startTime:A,endTime:F}of D)(k===void 0||A<k)&&(k=A),(f===void 0||F>f)&&(f=F);if(!k||!f)return;if((0,Dt.default)(f).diff((0,Dt.default)(k),"year")>5){kt.warn("The difference between the min and max time is more than 5 years. This will cause performance issues. Skipping drawing exclude days.");return}let _=s.db.getDateFormat(),r=[],u=null,a=(0,Dt.default)(k);for(;a.valueOf()<=f;)s.db.isInvalidDate(a,_,o,l)?u?u.end=a:u={start:a,end:a}:u&&(r.push(u),u=null),a=a.add(1,"d");g.append("g").selectAll("rect").data(r).enter().append("rect").attr("id",function(A){return"exclude-"+A.start.format("YYYY-MM-DD")}).attr("x",function(A){return y(A.start)+v}).attr("y",n.gridLineStartPadding).attr("width",function(A){let F=A.end.add(1,"day");return y(F)-y(A.start)}).attr("height",m-x-n.gridLineStartPadding).attr("transform-origin",function(A,F){return(y(A.start)+v+.5*(y(A.end)-y(A.start))).toString()+"px "+(F*p+.5*m).toString()+"px"}).attr("class","exclude-range")}c(N,"drawExcludeDays");function X(p,x,v,b){let m=Fe(y).tickSize(-b+x+n.gridLineStartPadding).tickFormat(Ot(s.db.getAxisFormat()||n.axisFormat||"%Y-%m-%d")),o=/^([1-9]\d*)(millisecond|second|minute|hour|day|week|month)$/.exec(s.db.getTickInterval()||n.tickInterval);if(o!==null){let l=o[1],k=o[2],f=s.db.getWeekday()||n.weekday;switch(k){case"millisecond":m.ticks(It.every(l));break;case"second":m.ticks(Lt.every(l));break;case"minute":m.ticks(Ft.every(l));break;case"hour":m.ticks(Yt.every(l));break;case"day":m.ticks(Wt.every(l));break;case"week":m.ticks(Pe[f].every(l));break;case"month":m.ticks(Vt.every(l));break}}if(g.append("g").attr("class","grid").attr("transform","translate("+p+", "+(b-50)+")").call(m).selectAll("text").style("text-anchor","middle").attr("fill","#000").attr("stroke","none").attr("font-size",10).attr("dy","1em"),s.db.topAxisEnabled()||n.topAxis){let l=Le(y).tickSize(-b+x+n.gridLineStartPadding).tickFormat(Ot(s.db.getAxisFormat()||n.axisFormat||"%Y-%m-%d"));if(o!==null){let k=o[1],f=o[2],_=s.db.getWeekday()||n.weekday;switch(f){case"millisecond":l.ticks(It.every(k));break;case"second":l.ticks(Lt.every(k));break;case"minute":l.ticks(Ft.every(k));break;case"hour":l.ticks(Yt.every(k));break;case"day":l.ticks(Wt.every(k));break;case"week":l.ticks(Pe[_].every(k));break;case"month":l.ticks(Vt.every(k));break}}g.append("g").attr("class","grid").attr("transform","translate("+p+", "+x+")").call(l).selectAll("text").style("text-anchor","middle").attr("fill","#000").attr("stroke","none").attr("font-size",10)}}c(X,"makeGrid");function B(p,x){let v=0,b=Object.keys(M).map(m=>[m,M[m]]);g.append("g").selectAll("text").data(b).enter().append(function(m){let D=m[0].split(ce.lineBreakRegex),o=-(D.length-1)/2,l=T.createElementNS("http://www.w3.org/2000/svg","text");l.setAttribute("dy",o+"em");for(let[k,f]of D.entries()){let _=T.createElementNS("http://www.w3.org/2000/svg","tspan");_.setAttribute("alignment-baseline","central"),_.setAttribute("x","10"),k>0&&_.setAttribute("dy","1em"),_.textContent=f,l.appendChild(_)}return l}).attr("x",10).attr("y",function(m,D){if(D>0)for(let o=0;o<D;o++)return v+=b[D-1][1],m[1]*p/2+v*p+x;else return m[1]*p/2+x}).attr("font-size",n.sectionFontSize).attr("class",function(m){for(let[D,o]of W.entries())if(m[0]===o)return"sectionTitle sectionTitle"+D%n.numberSectionStyles;return"sectionTitle"})}c(B,"vertLabels");function P(p,x,v,b){let m=s.db.getTodayMarker();if(m==="off")return;let D=g.append("g").attr("class","today"),o=new Date,l=D.append("line");l.attr("x1",y(o)+p).attr("x2",y(o)+p).attr("y1",n.titleTopMargin).attr("y2",b-n.titleTopMargin).attr("class","today"),m!==""&&l.attr("style",m.replace(/,/g,";"))}c(P,"drawToday");function V(p){let x={},v=[];for(let b=0,m=p.length;b<m;++b)Object.prototype.hasOwnProperty.call(x,p[b])||(x[p[b]]=!0,v.push(p[b]));return v}c(V,"checkUnique")},"draw"),Gr={setConf:Br,draw:Hr},Xr=c(t=>`
  .mermaid-main-font {
        font-family: ${t.fontFamily};
  }

  .exclude-range {
    fill: ${t.excludeBkgColor};
  }

  .section {
    stroke: none;
    opacity: 0.2;
  }

  .section0 {
    fill: ${t.sectionBkgColor};
  }

  .section2 {
    fill: ${t.sectionBkgColor2};
  }

  .section1,
  .section3 {
    fill: ${t.altSectionBkgColor};
    opacity: 0.2;
  }

  .sectionTitle0 {
    fill: ${t.titleColor};
  }

  .sectionTitle1 {
    fill: ${t.titleColor};
  }

  .sectionTitle2 {
    fill: ${t.titleColor};
  }

  .sectionTitle3 {
    fill: ${t.titleColor};
  }

  .sectionTitle {
    text-anchor: start;
    font-family: ${t.fontFamily};
  }


  /* Grid and axis */

  .grid .tick {
    stroke: ${t.gridColor};
    opacity: 0.8;
    shape-rendering: crispEdges;
  }

  .grid .tick text {
    font-family: ${t.fontFamily};
    fill: ${t.textColor};
  }

  .grid path {
    stroke-width: 0;
  }


  /* Today line */

  .today {
    fill: none;
    stroke: ${t.todayLineColor};
    stroke-width: 2px;
  }


  /* Task styling */

  /* Default task */

  .task {
    stroke-width: 2;
  }

  .taskText {
    text-anchor: middle;
    font-family: ${t.fontFamily};
  }

  .taskTextOutsideRight {
    fill: ${t.taskTextDarkColor};
    text-anchor: start;
    font-family: ${t.fontFamily};
  }

  .taskTextOutsideLeft {
    fill: ${t.taskTextDarkColor};
    text-anchor: end;
  }


  /* Special case clickable */

  .task.clickable {
    cursor: pointer;
  }

  .taskText.clickable {
    cursor: pointer;
    fill: ${t.taskTextClickableColor} !important;
    font-weight: bold;
  }

  .taskTextOutsideLeft.clickable {
    cursor: pointer;
    fill: ${t.taskTextClickableColor} !important;
    font-weight: bold;
  }

  .taskTextOutsideRight.clickable {
    cursor: pointer;
    fill: ${t.taskTextClickableColor} !important;
    font-weight: bold;
  }


  /* Specific task settings for the sections*/

  .taskText0,
  .taskText1,
  .taskText2,
  .taskText3 {
    fill: ${t.taskTextColor};
  }

  .task0,
  .task1,
  .task2,
  .task3 {
    fill: ${t.taskBkgColor};
    stroke: ${t.taskBorderColor};
  }

  .taskTextOutside0,
  .taskTextOutside2
  {
    fill: ${t.taskTextOutsideColor};
  }

  .taskTextOutside1,
  .taskTextOutside3 {
    fill: ${t.taskTextOutsideColor};
  }


  /* Active task */

  .active0,
  .active1,
  .active2,
  .active3 {
    fill: ${t.activeTaskBkgColor};
    stroke: ${t.activeTaskBorderColor};
  }

  .activeText0,
  .activeText1,
  .activeText2,
  .activeText3 {
    fill: ${t.taskTextDarkColor} !important;
  }


  /* Completed task */

  .done0,
  .done1,
  .done2,
  .done3 {
    stroke: ${t.doneTaskBorderColor};
    fill: ${t.doneTaskBkgColor};
    stroke-width: 2;
  }

  .doneText0,
  .doneText1,
  .doneText2,
  .doneText3 {
    fill: ${t.taskTextDarkColor} !important;
  }


  /* Tasks on the critical line */

  .crit0,
  .crit1,
  .crit2,
  .crit3 {
    stroke: ${t.critBorderColor};
    fill: ${t.critBkgColor};
    stroke-width: 2;
  }

  .activeCrit0,
  .activeCrit1,
  .activeCrit2,
  .activeCrit3 {
    stroke: ${t.critBorderColor};
    fill: ${t.activeTaskBkgColor};
    stroke-width: 2;
  }

  .doneCrit0,
  .doneCrit1,
  .doneCrit2,
  .doneCrit3 {
    stroke: ${t.critBorderColor};
    fill: ${t.doneTaskBkgColor};
    stroke-width: 2;
    cursor: pointer;
    shape-rendering: crispEdges;
  }

  .milestone {
    transform: rotate(45deg) scale(0.8,0.8);
  }

  .milestoneText {
    font-style: italic;
  }
  .doneCritText0,
  .doneCritText1,
  .doneCritText2,
  .doneCritText3 {
    fill: ${t.taskTextDarkColor} !important;
  }

  .activeCritText0,
  .activeCritText1,
  .activeCritText2,
  .activeCritText3 {
    fill: ${t.taskTextDarkColor} !important;
  }

  .titleText {
    text-anchor: middle;
    font-size: 18px;
    fill: ${t.titleColor||t.textColor};
    font-family: ${t.fontFamily};
  }
`,"getStyles"),qr=Xr,Jr={parser:ar,db:Nr,renderer:Gr,styles:qr};export{Jr as diagram};
