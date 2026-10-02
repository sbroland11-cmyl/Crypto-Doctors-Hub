const worldEarth=document.querySelector('.world-earth');
const worldGlow=document.querySelector('.world-glow');
const worldOrbits=[...document.querySelectorAll('.world-orbit')];
const heroCopy=document.querySelector('#hero-copy');
const heroStats=document.querySelector('#hero-stats');

let frame=0,lastWorldProgress=-1;
let worldTargetProgress=0;
let worldAnimatedProgress=0;
let lastScrollDirection=1;
let orbitFrame=0,lastOrbitTime=performance.now();
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const smoothstep=v=>v*v*(3-2*v);

// The Earth remains a clean circular 3D-looking globe. Its own slow axial-style
// motion is handled by CSS; the orbital rings remain separate from the globe.
const orbitSpecs=[
  {el:document.querySelector('.world-orbit-a'), node:document.querySelector('.world-orbit-a .orbit-node'), speed:0.19, phase:0.15, scale:1},
  {el:document.querySelector('.world-orbit-b'), node:document.querySelector('.world-orbit-b .orbit-node'), speed:-0.145, phase:2.1, scale:0.86},
  {el:document.querySelector('.world-orbit-c'), node:document.querySelector('.world-orbit-c .orbit-node'), speed:0.095, phase:4.15, scale:0.78}
];
function renderOrbitSystem(now){
  const dt=Math.min(40,now-lastOrbitTime);
  lastOrbitTime=now;


  orbitSpecs.forEach(o=>{
    if(!o.node)return;
    o.phase=(o.phase+dt/1000*o.speed)%(Math.PI*2);
    const rx=o.el.clientWidth*0.5;
    const ry=o.el.clientHeight*0.5;
    const x=Math.cos(o.phase)*rx;
    const y=Math.sin(o.phase)*ry;
    const depth=(Math.sin(o.phase)+1)*.5;
    const size=(.78+depth*.42)*o.scale;
    o.node.style.transform=`translate3d(${x}px,${y}px,0) scale(${size})`;
    o.node.style.opacity=String(.42+depth*.50);
    o.node.style.zIndex=String(Math.round(2+depth*4));
  });
  orbitFrame=requestAnimationFrame(renderOrbitSystem);
}

// The Earth artwork stays completely idle. Only the requested electric
// border/city-light effect animates over the map.
const electricCanvas=document.querySelector('#earth-electric');
let electricCtx=null;
let electricBase=null;
let electricW=0,electricH=0;
function buildElectricMap(){
  if(!electricCanvas)return;
  const img=document.querySelector('.earth-front img');
  if(!img || !img.complete || !img.naturalWidth)return;
  const size=480;
  electricW=electricH=size;
  electricCanvas.width=size; electricCanvas.height=size;
  const src=document.createElement('canvas'); src.width=size; src.height=size;
  const sctx=src.getContext('2d',{willReadFrequently:true}); sctx.drawImage(img,0,0,size,size);
  const d=sctx.getImageData(0,0,size,size).data;
  const out=document.createElement('canvas'); out.width=size; out.height=size;
  const octx=out.getContext('2d'); const od=octx.createImageData(size,size); const a=od.data;
  const lum=new Float32Array(size*size), warm=new Float32Array(size*size);
  for(let y=0;y<size;y++)for(let x=0;x<size;x++){
    const i=(y*size+x)*4,p=y*size+x;
    const r=d[i]/255,g=d[i+1]/255,b=d[i+2]/255,al=d[i+3]/255;
    lum[p]=(0.2126*r+0.7152*g+0.0722*b)*al;
    warm[p]=Math.max(0,(r-g)*1.8+(r-b)*.9)*al;
  }
  for(let y=2;y<size-2;y++)for(let x=2;x<size-2;x++){
    const p=y*size+x;
    const gx=-lum[p-size-1]-2*lum[p-1]-lum[p+size-1]+lum[p-size+1]+2*lum[p+1]+lum[p+size+1];
    const gy=-lum[p-size-1]-2*lum[p-size]-lum[p-size+1]+lum[p+size-1]+2*lum[p+size]+lum[p+size+1];
    const edge=Math.max(0,Math.min(1,(Math.hypot(gx,gy)-.055)*7.8));
    const city=Math.min(1,warm[p]*2.2+Math.max(0,lum[p]-.48)*1.35);
    const strength=Math.max(edge,edge*city*.92);
    if(strength<.13)continue;
    const dx=x-size/2,dy=y-size/2;
    if(Math.hypot(dx,dy)>size*.495)continue;
    const i=p*4; a[i]=180;a[i+1]=225;a[i+2]=255;a[i+3]=Math.round(255*Math.min(.72,strength*.72));
  }
  octx.putImageData(od,0,0); electricBase=out;
}
function renderElectric(now){
  if(!electricCtx || !electricBase){requestAnimationFrame(renderElectric);return;}
  const w=electricW,h=electricH,t=now*.00012;
  electricCtx.clearRect(0,0,w,h); electricCtx.save();
  electricCtx.globalCompositeOperation='source-over'; electricCtx.globalAlpha=.20; electricCtx.drawImage(electricBase,0,0);
  electricCtx.globalCompositeOperation='lighter'; electricCtx.globalAlpha=.95;
  const g=electricCtx.createLinearGradient(Math.cos(t)*w*.95,Math.sin(t)*h*.95,Math.cos(t+Math.PI)*w*.95,Math.sin(t+Math.PI)*h*.95);
  g.addColorStop(0,'rgba(120,205,255,0)');g.addColorStop(.39,'rgba(120,205,255,0)');g.addColorStop(.47,'rgba(230,250,255,.10)');g.addColorStop(.50,'rgba(255,255,255,.95)');g.addColorStop(.53,'rgba(120,205,255,.16)');g.addColorStop(.61,'rgba(120,205,255,0)');g.addColorStop(1,'rgba(120,205,255,0)');
  electricCtx.globalCompositeOperation='source-in'; electricCtx.fillStyle=g; electricCtx.fillRect(0,0,w,h); electricCtx.restore();
  requestAnimationFrame(renderElectric);
}
function initElectric(){
  if(!electricCanvas)return; electricCtx=electricCanvas.getContext('2d');
  const img=document.querySelector('.earth-front img');
  if(img && img.complete)buildElectricMap(); else if(img)img.addEventListener('load',buildElectricMap,{once:true});
  requestAnimationFrame(renderElectric);
}

function worldRender(now=performance.now()){
  frame=0;
  const maxScroll=Math.max(1,document.documentElement.scrollHeight-innerHeight);
  const target=clamp(scrollY/maxScroll,0,1);
  const delta=target-worldAnimatedProgress;
  lastScrollDirection=delta>=0?1:-1;

  // Animate the visual progress toward the real scroll position instead of
  // applying the raw scroll value directly. This keeps expansion smooth and,
  // importantly, gives the contraction on scroll-up the same fluid motion.
  const dt=Math.min(50,now-(worldRender.lastTime||now));
  worldRender.lastTime=now;
  const response=0.20;
  const blend=1-Math.exp(-response*Math.max(16,dt)/16.67);
  worldAnimatedProgress += delta*blend;
  if(Math.abs(target-worldAnimatedProgress)<0.00008) worldAnimatedProgress=target;

  const p=worldAnimatedProgress;
  if(Math.abs(p-lastWorldProgress)<0.00008 && p===target)return;
  lastWorldProgress=p;

  // Earth expansion follows the full document from the first scroll movement
  // to the final scroll position, using the eased visual progress above.
  const growth=p;
  const scale=.46 + growth*4.15;
  const y=19 - growth*7.5;
  worldEarth.style.transform=`translate3d(0,${y}vh,0) scale(${scale})`;

  // Keep the globe fully detailed at the start. The inner Earth/map/city-light
  // content then fades progressively with page scroll: ~50% of its content is
  // gone at ~50% page progress, and the detailed content is gone at the end.
  const fadeProgress=clamp((p-0.005)/0.76,0,1);
  const baseEarthContentOpacity=1-smoothstep(fadeProgress);
  // By 20% page scroll, strengthen the globe transparency and blur by 40%.
  const scroll20Boost=smoothstep(clamp((p-0.02)/0.18,0,1));
  const earthContentOpacity=clamp(baseEarthContentOpacity*(1-0.40*scroll20Boost),0,1);
  const backgroundSoft=smoothstep(clamp(p/0.92,0,1));
  const earthRimOpacity=.07 + earthContentOpacity*.27;
  const blurBoost=1 + 0.20*scroll20Boost;
  const earthBlur=backgroundSoft*0.95*blurBoost;

  worldGlow.style.opacity='0';
  worldEarth.style.opacity=String(earthRimOpacity);
  worldEarth.style.filter='none';
  worldEarth.style.setProperty('--earth-blur',`${earthBlur.toFixed(2)}px`);
  worldEarth.style.setProperty('--earth-content-opacity',String(earthContentOpacity));
  worldEarth.style.setProperty('--earth-mask',String(fadeProgress));
  worldEarth.style.setProperty('--bg-soft',String(backgroundSoft));
  document.querySelector('.world-layer')?.style.setProperty('--world-soften',String(backgroundSoft));

  const heroP=clamp(scrollY/(innerHeight*.95),0,1);
  const h=smoothstep(heroP);
  heroCopy.style.transform=`translate3d(-50%,${-h*24}vh,0) scale(${1-h*.08})`;
  heroCopy.style.opacity=String(1-h*.96);
  heroStats.style.opacity='1';

  // Keep the animation loop alive until the eased globe catches the real
  // scroll position. This is what makes rapid scroll-up contraction smooth.
  if(Math.abs(worldTargetProgress-worldAnimatedProgress)>0.00008){
    frame=requestAnimationFrame(worldRender);
  }
}
function requestWorldRender(){
  const maxScroll=Math.max(1,document.documentElement.scrollHeight-innerHeight);
  worldTargetProgress=clamp(scrollY/maxScroll,0,1);
  if(!frame)frame=requestAnimationFrame(worldRender);
}
addEventListener('scroll',requestWorldRender,{passive:true});
addEventListener('resize',requestWorldRender,{passive:true});
requestWorldRender();
if(!orbitFrame)orbitFrame=requestAnimationFrame(renderOrbitSystem);
initElectric();

// CDH ecosystem options — scroll-driven popup, with every option always visible.
// The animation is transform-only: no opacity/display hiding is ever used.
const featureTiles=[...document.querySelectorAll('.ecosystem-section .feature-tile')];
let featureScrollFrame=0;
function updateFeaturePopup(){
  featureScrollFrame=0;
  const vh=window.innerHeight||800;
  const trigger=vh*0.92;
  const settle=vh*0.62;
  featureTiles.forEach((tile)=>{
    const rect=tile.getBoundingClientRect();
    const progress=clamp((trigger-rect.top)/(trigger-settle),0,1);
    // Never hide a card. Before it reaches the viewport it simply sits a
    // little lower; while scrolling down it rises smoothly into place.
    const y=(1-progress)*52;
    const scale=.985 + progress*.015;
    tile.style.opacity='1';
    tile.style.visibility='visible';
    tile.style.setProperty('--scroll-y',`${y.toFixed(2)}px`);
    tile.style.setProperty('--scroll-scale',scale.toFixed(4));
    if(progress>0.985 && !tile.dataset.scrollSettled){
      tile.dataset.scrollSettled='1';
      tile.classList.remove('scroll-sweep');
      void tile.offsetWidth;
      tile.classList.add('scroll-sweep');
    }
  });
}
function requestFeaturePopup(){
  if(!featureScrollFrame) featureScrollFrame=requestAnimationFrame(updateFeaturePopup);
}
addEventListener('scroll',requestFeaturePopup,{passive:true});
addEventListener('resize',requestFeaturePopup,{passive:true});
requestFeaturePopup();

// ===== CDH APP DOWNLOAD DESTINATIONS =====
// Replace these placeholder URLs with your real distribution links.
// Android: direct HTTPS APK URL (or Google Play URL later).
// iOS: intentionally disabled for now — shown as Coming Soon on the website.
// Web: your deployed CDH web-app URL.
// Desktop: direct HTTPS installer/build URL.
window.CDH_APP_DOWNLOADS = {
  // OWNER EDIT: replace these empty strings with real HTTPS destinations.
  android: '',
  web: '',
  desktop: '',
  androidMeta: 'APK / Google Play',
  webMeta: 'Open CDH in browser',
  desktopMeta: 'Windows / Desktop Build',
  androidVersion: '',
  androidSize: '',
  androidSha256: ''
};
Object.entries(downloadLinks).forEach(([key,el])=>{
  if(!el)return;
  const url=String(window.CDH_APP_DOWNLOADS[key]||'').trim();
  const meta=document.querySelector(`#download-${key}-meta`);
  const configured=!!url;
  el.href=configured?url:'#';
  el.setAttribute('aria-disabled',configured?'false':'true');
  el.classList.toggle('download-option-disabled',!configured);
  if(!configured){
    el.removeAttribute('target'); el.setAttribute('tabindex','-1');
    if(meta)meta.textContent='Download link not configured yet';
  }else{
    el.setAttribute('target','_blank'); el.removeAttribute('tabindex');
    if(meta){
      const base=window.CDH_APP_DOWNLOADS[`${key}Meta`]||'';
      if(key==='android'){
        const extras=[window.CDH_APP_DOWNLOADS.androidVersion,window.CDH_APP_DOWNLOADS.androidSize].filter(Boolean).join(' · ');
        meta.textContent=extras?`${base} · ${extras}`:base;
      }else meta.textContent=base;
    }
  }
});
Object.entries(downloadLinks).forEach(([key,el])=>el?.addEventListener('click',e=>{if(!String(window.CDH_APP_DOWNLOADS[key]||'').trim())e.preventDefault();}));
function openDownloadModal(){
  if(!downloadModal)return;
  downloadModal.classList.add('is-open');downloadModal.setAttribute('aria-hidden','false');document.body.classList.add('modal-open');
  downloadModal.querySelector('.download-close')?.focus();
}
function closeDownloadModal(){
  if(!downloadModal)return;
  downloadModal.classList.remove('is-open');downloadModal.setAttribute('aria-hidden','true');document.body.classList.remove('modal-open');
}
downloadTrigger?.addEventListener('click',openDownloadModal);
downloadModal?.querySelectorAll('[data-download-close]').forEach(el=>el.addEventListener('click',closeDownloadModal));
addEventListener('keydown',e=>{if(e.key==='Escape'&&downloadModal?.classList.contains('is-open'))closeDownloadModal();});

// Ecosystem tabs.
const tabs=[...document.querySelectorAll('.glass-tabs button')];
const tabKicker=document.querySelector('#tab-kicker');
const tabTitle=document.querySelector('#tab-title');
const tabText=document.querySelector('#tab-text');
const tabContent=[
 ['CDH PLATFORM','A complete crypto experience.','A focused environment for information, execution, education and long-term development.'],
 ['TRADING','Information built for action.','Analysis, Live Calls and a structured Trading Journal connect insight with disciplined execution.'],
 ['LEARNING','Build a framework that lasts.','Mentorship turns complex market concepts into a repeatable process through structured learning and practice.'],
 ['COMMUNITY','Move with the community.','Profiles, CD Feed, Alpha Den and community experiences keep ideas, progress and people connected.']
];
tabs.forEach((tab,i)=>tab.addEventListener('click',()=>{
 tabs.forEach(x=>x.classList.remove('active'));tab.classList.add('active');
 const d=tabContent[i];tabKicker.textContent=d[0];tabTitle.textContent=d[1];tabText.textContent=d[2];
}));

// Active navigation.
const navLinks=[...document.querySelectorAll('.main-nav a')];
const sections=navLinks.map(a=>document.querySelector(a.getAttribute('href'))).filter(Boolean);
const observer=new IntersectionObserver(entries=>{
 entries.forEach(entry=>{
  if(entry.isIntersecting){
   navLinks.forEach(a=>a.classList.toggle('active',a.getAttribute('href')===`#${entry.target.id}`));
  }
 });
},{rootMargin:'-48% 0px -48% 0px',threshold:0});
sections.forEach(s=>observer.observe(s));

// Premium horizontal carousel: native scrolling + desktop mouse drag + touch.
// The viewport is the scroll container; the previous version incorrectly tried
// to change scrollLeft on the non-scrollable track itself.
const viewport=document.querySelector('.drag-viewport');
const track=document.querySelector('#drag-track');
const prev=document.querySelector('#prev');
const next=document.querySelector('#next');
let drag=false,startX=0,startScroll=0;
function cardStep(){
  const card=track.querySelector('.experience-card');
  return (card?.getBoundingClientRect().width || 430)+18;
}
function moveBy(dir){
  viewport.scrollBy({left:dir*cardStep(),behavior:'smooth'});
}
prev?.addEventListener('click',()=>moveBy(-1));
next?.addEventListener('click',()=>moveBy(1));
viewport?.addEventListener('pointerdown',e=>{
  if(e.pointerType==='touch')return;
  drag=true;startX=e.clientX;startScroll=viewport.scrollLeft;
  viewport.setPointerCapture(e.pointerId);track.classList.add('dragging');
});
viewport?.addEventListener('pointermove',e=>{
  if(!drag)return;
  viewport.scrollLeft=startScroll-(e.clientX-startX);
});
const stopDrag=()=>{drag=false;track.classList.remove('dragging')};
viewport?.addEventListener('pointerup',stopDrag);
viewport?.addEventListener('pointercancel',stopDrag);
viewport?.addEventListener('lostpointercapture',stopDrag);

// Typewriter is bootstrapped directly in the HTML so it cannot be blocked by
// optional page interactions or another runtime error.

// ===== CDH FEATURE DETAIL SYSTEM =====
const featureData={
 feed:{index:'01',category:'COMMUNITY',title:'CD Feed',summary:'Your crypto community feed — the social layer where market information, ideas, shared calls and ecosystem content meet.',badges:['Create Post','Share Idea','Share Signal','Community'],features:['Create posts','Share ideas and trading signals','Image posts','Likes and comments','Reposts and views','Follow creators','Trending community content','Crypto market information','Top crypto assets','Shared Live Calls','Alpha Den content','Mentorship content'],rules:['The feed is the main community discovery layer.','Creators can publish ideas, signals and images.','Community interaction includes likes, comments, reposts, views and follows.','Shared Live Calls and ecosystem content can appear in the feed.']},
 analysis:{index:'02',category:'INTELLIGENCE',title:'CD Analysis',summary:'Professional market analysis designed to explain what the market is doing and why the information matters.',badges:['Market Analysis','Charts','Bull / Bear','Important Analysis'],features:['Professional market analysis','Market analysis','Bull analysis','Bear analysis','Charts','Analysis images','Market explanation','Important analysis','Share to CD Feed','View analysis','Community interaction'],rules:['Analysis is presented as structured market information and explanation.','Bull and Bear analysis are descriptive analysis formats.','Analysis can include charts and supporting images.','Important analysis can be shared into CD Feed for wider community context.']},
 live:{index:'03',category:'EXECUTION',title:'Live Calls',summary:'Real-time trading calls with clear trade structure, premium access controls and permanent closed outcomes.',badges:['LONG','SHORT','TP1','TP2','TP3','Stop Loss'],features:['Live Call #1','Live Call #2','Premium Live Calls','Long / Short','Entry','TP1 / TP2 / TP3','Stop Loss','Leverage','Trade result','Closed Green / Closed Red','Took This Trade','Trade result / loss','Daily performance','Win percentage','Total trades','Green wins','Red losses','Daily signal count','Signal information','Risk Management'],rules:['Live Calls use Long / Short rather than Bull / Bear controls.','Each call contains entry, TP1, TP2, TP3, stop loss and leverage where applicable.','The first two daily calls can be public; remaining protected calls use Premium access.','A closed trade has a permanent green or red result.','The journal can use Took This Trade / loss interaction to track participation.','Users can open Signal Information and Risk Management information from the call experience.']},
 premium:{index:'04',category:'ACCESS',title:'Premium',summary:'Premium membership adds protected Live Calls, full signal information and a recognizable premium profile identity.',badges:['⭐ Premium','💜 Lifetime Premium','$15 Monthly','$50 Lifetime'],features:['Premium Monthly — $15/month','Premium Lifetime — $50 one-time','Premium badge','All Live Calls','Premium signal access','Full signal information','Premium trading experience','Premium profile identity','Premium badges'],rules:['Premium access is a membership state, not a visual-only label.','Protected Live Call information remains restricted until access is granted.','Premium identity can appear consistently wherever a profile is represented.','The website presents membership information; actual access is controlled by the CDH app/backend.']},
 alpha:{index:'05',category:'CREATORS',title:'Alpha Den',summary:'A dedicated creator and trading-idea community inside CDH — your way to Web 3.0.',badges:['Post Idea','Post Signal','Creator Activity','Verified Creator'],features:['Alpha Den profile','Username','Nickname','Post idea','Post signal','Trading ideas','Charts','Images','Likes','Comments','Reposts','Views','Followers','Creator activity','Creator achievements','Verified creator'],rules:['Creators can publish ideas and signals as distinct post types.','Profiles expose creator identity through username and nickname.','Community activity includes likes, comments, reposts, views and followers.','Verified Creator recognition can appear alongside creator content.']},
 mentorship:{index:'06',category:'EDUCATION',title:'Mentorship',summary:'A structured educational experience covering crypto foundations, technical analysis, practical application and risk management.',badges:['$80 One-Time','$20 × 4 Installment','Student 1','Student 2','Student 3','Student 4','Graduated'],features:['Daily lessons','Video lessons','Lesson notes','Crypto education','Market analysis','Technical analysis','Practical application','Backtesting','Risk management','Live classes','Student community','Student progress','Graduation','One-time — $80','Installment — $20 × 4'],rules:['Mentorship information appears before the payment choice.','The one-time plan is $80.','The installment plan is $20 × 4.','Student progress can be represented by Student 1, Student 2, Student 3, Student 4 and Graduated badges.','Lessons can include video and notes.','Risk management, backtesting and practical application are core learning areas.']},
 chat:{index:'07',category:'STUDENTS',title:'Mentorship Chat',summary:'A private, moderated student community for communication, learning and updates.',badges:['Student Community','Moderated','Private Chat'],features:['Student community','Private student chat','Admin communication','Likes','Dislikes','Emoji reactions','Image / screenshot sharing','Student updates','Moderated community'],rules:['The chat is dedicated to eligible mentorship students.','Admin communication is available inside the student environment.','Students can react and share relevant screenshots or images.','Moderation keeps the student space focused and structured.']},
 journal:{index:'08',category:'PERFORMANCE',title:'Trading Journal',summary:'A long-term performance layer that organizes your trading journey by day, week, month and year.',badges:['Daily','Weekly','Monthly','Yearly'],features:['Personal journal','Community journal','Daily community profit','Monthly community profit','Yearly community profit','Trading tasks','Profit target','Risk management','Trade history','Winning trades','Losing trades','Performance tracking','Trading achievements','5+ win trades','8+ win trades','10+ win trades'],rules:['Journal views are Daily, Weekly, Monthly and Yearly.','Community profit and personal journal information are separate views.','Trade history records winning and losing trades after official outcomes are closed.','Trading tasks can include profit targets and risk-management goals.','Achievements can reflect 5+, 8+ and 10+ winning trades.']},
 referral:{index:'09',category:'GROWTH',title:'Referral System',summary:'Invite people into CDH, track your referrals and build rewards through a clear referral structure.',badges:['Invite','Earn','Grow'],features:['Personal referral link','Referred users','Referral rewards','Referral history','Referral achievements','Crown progress','Premium Monthly → $4','Premium Lifetime → $12','Mentorship One-Time → $20','Mentorship Installment → $5 per confirmed installment'],rules:['Each user can have a personal referral link.','Referred users and reward history can be tracked.','Reward amounts shown here are the CDH referral structure supplied for the platform.','Crown progress is connected to referral milestones.']},
 crown:{index:'10',category:'REPUTATION',title:'Crown System',summary:'A community reputation system where referral milestones unlock progressively stronger crown identities.',badges:['Brown','Blue','Purple','Golden','Black + Gold'],features:['Brown Crown — 0 referrals','Blue Crown — 1–2 referrals','Purple Crown — 3–4 referrals','Golden Crown — 5–9 referrals','Black + Gold Crown — 10+ referrals','Enhanced glow effects','Flame-style visual appearance'],rules:['Crown level is based on referral count.','Brown starts at 0 referrals.','Blue is 1–2, Purple is 3–4, Golden is 5–9 and Black + Gold is 10+.','Higher levels can use enhanced glow and the established flame-style appearance.']},
 verified:{index:'11',category:'CREATOR IDENTITY',title:'Verified Creator',summary:'Creator recognition that gives an established profile a clear verified identity across CDH.',badges:['🔵 Verified Tick','Creator Recognition'],features:['Verified tick','Creator profile','Ideas','Signals','Trading content','Community','Content promotion'],rules:['The verified state is presented as a creator recognition layer.','The badge can accompany creator ideas, signals and trading content.','Verified identity should remain visually consistent wherever the creator appears.']},
 badges:{index:'12',category:'ACHIEVEMENTS',title:'Profile & Badges',summary:'A visual identity layer that collects Premium, student, crown, creator and trading achievements.',badges:['⭐ Premium','🎓 Student','👑 Crown','🔵 Verified'],features:['Personal profile','Profile picture','Nickname','Username','Crown','Premium badge','Student badge','Graduation badge','Win trade achievements','Verified badge','Trading achievements','Followers','Referral','Badge collection','Premium','Lifetime Premium','Brown / Blue / Purple / Golden / Black + Gold Crown','Student 1–4','Graduated','Verified Creator','Win Trade Achievements','Elite Trading Achievement'],rules:['Badges communicate a specific status or achievement.','Crown sits beside the nickname before other badges in the profile identity hierarchy.','Premium, student, graduation, verified and trading achievements can appear across profile representations.','Badges can be opened for compact information about what they mean and how they were earned.']},
 payments:{index:'13',category:'PAYOUTS',title:'Payment Details',summary:'Your own payout information for receiving platform earnings — separate from CDH platform receiving details.',badges:['BEP20','TRC20','ERC20','Easypaisa'],features:['USDT BEP20','USDT TRC20','USDT ERC20','Easypaisa','Name','UID','Wallet / payout details','Easy copy'],rules:['Payment Details refers to the user payout destination.','Crypto methods support USDT on BEP20, TRC20 and ERC20.','Easypaisa is supported as a payout method.','Saved details are associated with the user account and can be surfaced to authorized payout processing.']},
 support:{index:'14',category:'HELP',title:'Customer Support',summary:'A focused help center for tickets, conversations and support status.',badges:['Ticket','Conversation','Status'],features:['Submit ticket','My tickets','Ticket ID','Ticket conversation','Ticket updates','Open','Awaiting User','Closed'],rules:['Each support request has a ticket identity.','Users can review their tickets and conversations.','Ticket status can show Open, Awaiting User or Closed.','Updates can keep the user informed as the conversation progresses.']},
 notifications:{index:'15',category:'UPDATES',title:'Mail / Notifications',summary:'Your CDH update layer for achievements, rewards, student information, Premium changes and platform announcements.',badges:['Rewards','Announcements','Updates'],features:['Notifications','Achievement rewards','Student updates','Premium updates','Crown updates','Referral updates','Platform announcements','Badge collection'],rules:['Notifications keep important platform changes visible to the user.','Achievement, student, Premium, crown and referral updates can be surfaced separately.','Platform announcements provide a dedicated channel for important CDH information.']},
 openclass:{index:'16',category:'LEARNING',title:'Open Class',summary:'A dedicated educational and community-learning area for open CDH content.',badges:['Classes','Educational Content','Learning Material'],features:['Classes','Educational content','Learning material','Community learning'],rules:['Open Class is distinct from paid Mentorship.','It can host educational content and learning material for the broader community.','Community learning can connect open education with discussion and discovery.']},
 market:{index:'17',category:'MARKET',title:'Crypto Market',summary:'A live market information layer covering major assets, price movement and market context.',badges:['BTC','ETH','SOL','XRP','DOGE','Top 100'],features:['Market overview','BTC','ETH','SOL','XRP','DOGE','Top 100 crypto assets','Live prices','Market information','Price movement','Crypto logos'],rules:['The market area is informational and focused on current crypto market data.','Top assets can be surfaced through dedicated cards.','Price movement and market information are presented as a connected market layer.']},
 themes:{index:'18',category:'EXPERIENCE',title:'Themes',summary:'A professional visual system with a matte dark experience and a clean creamy light experience.',badges:['Dark','Light','Glass UI'],features:['Dark theme','Matte black background','Glass UI','Existing cards','Existing buttons','Clean professional interface','Light theme','Creamy white background','Clean cards','Clear controls','Professional light interface'],rules:['Dark Theme uses a matte black background while preserving the established cards, buttons and glass UI.','Light Theme uses a creamy white background with clear controls and professional contrast.','The existing animated visual atmosphere remains part of the dark experience where applicable.']},
 personal:{index:'19',category:'ACCOUNT',title:'Personal',summary:'Your CDH account control center — profile identity, achievements, referrals, payments, notifications and access status.',badges:['Profile','Badges','Status'],features:['Edit profile','My badges','My achievements','Referral','Payment Details','Theme','Notifications','Mail','Mentorship status','Premium status','Logout'],rules:['Personal is the user account layer.','Profile identity, badges and achievements are managed from the personal area.','Premium and Mentorship status can be surfaced here.','Payment Details is for the user payout information.','Theme and notification preferences belong to the personal experience.']}
};
const modal=document.querySelector('#feature-modal');
const modalIndex=document.querySelector('#modal-index');
const modalCategory=document.querySelector('#modal-category');
const modalTitle=document.querySelector('#modal-title');
const modalSummary=document.querySelector('#modal-summary');
const modalBadges=document.querySelector('#modal-badges');
const modalFeatures=document.querySelector('#modal-features');
const modalRules=document.querySelector('#modal-rules');
function fillList(el,items){el.innerHTML=items.map(x=>`<li>${x}</li>`).join('');}
function openFeature(key){
  const d=featureData[key];if(!d||!modal)return;
  modalIndex.textContent=d.index;modalCategory.textContent=d.category;modalTitle.textContent=d.title;modalSummary.textContent=d.summary;
  const badgeIcon=(label)=>{const t=label.toLowerCase();if(t.includes('premium')||t.includes('lifetime'))return '✦';if(t.includes('student'))return '♙';if(t.includes('graduated'))return '◆';if(t.includes('verified')||t.includes('tick'))return '✓';if(t.includes('crown')||t.includes('brown')||t.includes('blue')||t.includes('purple')||t.includes('golden')||t.includes('black + gold'))return '♛';if(t.includes('win')||t.includes('daily')||t.includes('weekly')||t.includes('monthly')||t.includes('yearly'))return '↗';if(t.includes('signal')||t.includes('long')||t.includes('short')||t.includes('tp')||t.includes('stop'))return '⚡';if(t.includes('post')||t.includes('idea')||t.includes('creator'))return '◇';if(t.includes('bep20')||t.includes('trc20')||t.includes('erc20')||t.includes('usdt'))return '₿';if(t.includes('easypaisa')||t.includes('payment'))return '₱';if(t.includes('invite')||t.includes('earn')||t.includes('grow'))return '↗';if(t.includes('chat')||t.includes('community'))return '••';if(t.includes('dark')||t.includes('light')||t.includes('glass'))return '◐';if(t.includes('btc')||t.includes('eth')||t.includes('sol')||t.includes('xrp')||t.includes('doge'))return '₿';return '◆'};
  modalBadges.innerHTML=d.badges.map((x,i)=>`<span class="result-badge"><i class="result-badge-art">${badgeIcon(x)}</i><b>${x}</b><em>${i+1}</em></span>`).join('');fillList(modalFeatures,d.features);fillList(modalRules,d.rules);
  modal.classList.add('is-open');modal.setAttribute('aria-hidden','false');document.body.classList.add('modal-open');
  const close=modal.querySelector('.modal-close');if(close)close.focus();
}
function closeFeature(){if(!modal)return;modal.classList.remove('is-open');modal.setAttribute('aria-hidden','true');document.body.classList.remove('modal-open');}
document.querySelectorAll('.feature-tile').forEach(tile=>tile.addEventListener('click',()=>openFeature(tile.dataset.feature)));
modal?.querySelectorAll('[data-modal-close]').forEach(el=>el.addEventListener('click',closeFeature));
addEventListener('keydown',e=>{if(e.key==='Escape'&&modal?.classList.contains('is-open'))closeFeature();});
