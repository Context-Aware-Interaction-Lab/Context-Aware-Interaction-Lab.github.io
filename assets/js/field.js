(() => {
 const hero = document.querySelector('.hero');
 const canvas = hero && hero.querySelector('.field');
 const ctx = canvas && canvas.getContext('2d');
 if (!ctx) return;
 const readout = hero.querySelector('.field-readout__time');
 const root = getComputedStyle(document.documentElement);
 const hex = h => { h = h.trim().replace('#',''); return [0,2,4].map(i => parseInt(h.slice(i,i+2),16)); };
 const stops = [1,2,3,4,5,6].map(i => hex(root.getPropertyValue('--spec-'+i)));
 const clamp = (v,a,b) => Math.min(b, Math.max(a, v));
 const mq = matchMedia('(prefers-reduced-motion: reduce)');

 // spectrum sample, u in 0..1 (warm to cool)
 const spec = u => {
  const f = clamp(u,0,1) * 5, i = Math.min(4, Math.floor(f)), t = f - i;
  return stops[i].map((c,k) => c + (stops[i+1][k] - c) * t);
 };

 // Singapore time; ?hour=14.5 previews a time
 const fmt = new Intl.DateTimeFormat('en-GB', {timeZone:'Asia/Singapore', hour:'2-digit', minute:'2-digit', hourCycle:'h23'});
 const override = parseFloat(new URLSearchParams(location.search).get('hour'));
 const sgTime = () => {
  const p = Object.fromEntries(fmt.formatToParts(new Date()).map(x => [x.type, x.value]));
  const h = +p.hour + (+p.minute)/60;
  return {h: isNaN(override) ? h : override, label: p.hour + ':' + p.minute};
 };
 // 0 = warm (13:00), 1 = cool (01:00)
 const coolness = h => 0.5 - 0.5 * Math.cos(2*Math.PI*(h - 13)/24);

 let W = 0, H = 0, dpr = 1, nodes = [], L = 120;
 let cool = 0, coolTarget = 0;
 const cur = {x:0, y:0, tx:0, ty:0, a:0, ta:0};
 let visible = true, pageVisible = !document.hidden, raf = 0, last = 0;

 const refreshTime = () => {
  const t = sgTime();
  coolTarget = coolness(t.h);
  if (readout) readout.textContent = isNaN(override) ? t.label : String(override);
 };

 const size = () => {
  const r = hero.getBoundingClientRect();
  const nw = Math.round(r.width), nh = Math.round(r.height);
  if (!nw || !nh || (nw === W && nh === H)) return;
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = nw*dpr; canvas.height = nh*dpr;
  ctx.setTransform(dpr,0,0,dpr,0,0);
  const count = clamp(Math.round(nw*nh/6500), 44, 180);
  if (!nodes.length) {
   for (let i=0;i<count;i++) nodes.push({x:Math.random()*nw, y:Math.random()*nh, bx:0, by:0, vx:0, vy:0, s:Math.random()*2-1, r:2+Math.random()*2.8});
   nodes.forEach(n => { const a = Math.random()*6.283, v = 5+Math.random()*9; n.bx = Math.cos(a)*v; n.by = Math.sin(a)*v; n.vx = n.bx; n.vy = n.by; });
  } else {
   nodes.forEach(n => { n.x *= nw/(W||nw); n.y *= nh/(H||nh); });
   while (nodes.length > count) nodes.pop();
   while (nodes.length < count) nodes.push({x:Math.random()*nw, y:Math.random()*nh, bx:6, by:4, vx:6, vy:4, s:Math.random()*2-1, r:2+Math.random()*2.8});
  }
  W = nw; H = nh;
  L = clamp(Math.min(W,H)*0.2, 100, 165);
  draw();
 };

 const step = dt => {
  cool += (coolTarget - cool) * Math.min(1, dt*0.8);
  cur.x += (cur.tx - cur.x) * Math.min(1, dt*8);
  cur.y += (cur.ty - cur.y) * Math.min(1, dt*8);
  cur.a += (cur.ta - cur.a) * Math.min(1, dt*4);
  const R = 220;
  for (const n of nodes) {
   let ax = 0, ay = 0, inf = 0;
   if (cur.a > 0.01) {
    const dx = cur.x - n.x, dy = cur.y - n.y, d = Math.hypot(dx,dy) || 1;
    if (d < R) {
     inf = (1 - d/R) * cur.a;
     const f = d < 55 ? -1.2 : 1;
     ax = dx/d * inf * 70 * f; ay = dy/d * inf * 70 * f;
    }
   }
   n.inf = inf;
   n.vx += ((n.bx - n.vx)*0.9 + ax) * dt;
   n.vy += ((n.by - n.vy)*0.9 + ay) * dt;
   n.x += n.vx*dt; n.y += n.vy*dt;
   if (n.x < -10) n.x = W+10; else if (n.x > W+10) n.x = -10;
   if (n.y < -10) n.y = H+10; else if (n.y > H+10) n.y = -10;
  }
 };

 function draw() {
  ctx.clearRect(0,0,W,H);
  const center = 0.12 + 0.76*cool;
  for (const n of nodes) {
   const c = spec(center + n.s*0.3 - (n.inf||0)*0.2);
   n.c = c;
  }
  ctx.lineWidth = 1;
  for (let i=0;i<nodes.length;i++) {
   const a = nodes[i];
   for (let j=i+1;j<nodes.length;j++) {
    const b = nodes[j];
    const dx = a.x-b.x, dy = a.y-b.y;
    const lim = L * (1 + 0.8*Math.max(a.inf||0, b.inf||0));
    const d2 = dx*dx + dy*dy;
    if (d2 > lim*lim) continue;
    const k = 1 - Math.sqrt(d2)/lim;
    const m = [0,1,2].map(q => (a.c[q]+b.c[q])/2|0);
    ctx.strokeStyle = `rgba(${m[0]},${m[1]},${m[2]},${(0.12 + 0.5*k).toFixed(3)})`;
    ctx.beginPath(); ctx.moveTo(a.x,a.y); ctx.lineTo(b.x,b.y); ctx.stroke();
   }
  }
  for (const n of nodes) {
   const r = n.r * (1 + (n.inf||0)*0.9);
   ctx.fillStyle = `rgba(${n.c[0]|0},${n.c[1]|0},${n.c[2]|0},0.12)`;
   ctx.beginPath(); ctx.arc(n.x,n.y,r*2.6,0,6.283); ctx.fill();
   ctx.fillStyle = `rgb(${n.c[0]|0},${n.c[1]|0},${n.c[2]|0})`;
   ctx.beginPath(); ctx.arc(n.x,n.y,r,0,6.283); ctx.fill();
  }
  hero.classList.add('is-live');
 }

 const frame = ts => {
  const dt = Math.min(0.05, (ts - last)/1000 || 0.016);
  last = ts;
  step(dt); draw();
  raf = requestAnimationFrame(frame);
 };
 const update = () => {
  const run = visible && pageVisible && !mq.matches;
  if (run && !raf) { last = performance.now(); raf = requestAnimationFrame(frame); }
  if (!run && raf) { cancelAnimationFrame(raf); raf = 0; }
 };

 hero.addEventListener('pointermove', e => {
  const r = hero.getBoundingClientRect();
  cur.tx = e.clientX - r.left; cur.ty = e.clientY - r.top;
  if (!cur.ta) { cur.x = cur.tx; cur.y = cur.ty; }
  cur.ta = 1;
 });
 ['pointerleave','pointercancel'].forEach(t => hero.addEventListener(t, () => { cur.ta = 0; }));
 new IntersectionObserver(es => { visible = es[0].isIntersecting; update(); }).observe(hero);
 document.addEventListener('visibilitychange', () => { pageVisible = !document.hidden; update(); });
 new ResizeObserver(size).observe(hero);
 mq.addEventListener('change', () => { cool = coolTarget; draw(); update(); });
 refreshTime(); cool = coolTarget;
 setInterval(refreshTime, 30000);
 size(); draw(); update();
})();
