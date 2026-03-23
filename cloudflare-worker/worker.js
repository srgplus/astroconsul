const MAINTENANCE_HTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>big3.me — Обновляемся</title>
<meta http-equiv="refresh" content="12">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%;overflow:hidden}
body{
  background:#0a0a0f;
  color:#fff;
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  display:flex;
  align-items:center;
  justify-content:center;
  text-align:center;
}

/* star field */
.stars{position:fixed;inset:0;pointer-events:none;overflow:hidden}
.star{
  position:absolute;
  width:2px;height:2px;
  border-radius:50%;
  background:#fff;
  animation:twinkle var(--d,3s) ease-in-out infinite alternate;
  opacity:0;
}
@keyframes twinkle{0%{opacity:0;transform:scale(0.5)}100%{opacity:var(--o,0.6);transform:scale(1)}}

/* zodiac ring */
.ring-wrap{position:relative;width:200px;height:200px;margin:0 auto 32px}
.ring{
  width:200px;height:200px;
  border:2px solid rgba(168,85,247,0.25);
  border-radius:50%;
  animation:spin 60s linear infinite;
  position:relative;
}
.ring::before{
  content:'';position:absolute;inset:-2px;
  border-radius:50%;
  border:2px solid transparent;
  border-top-color:#a855f7;
  border-right-color:#ec4899;
  animation:spin 8s linear infinite;
}
@keyframes spin{to{transform:rotate(360deg)}}

/* zodiac glyphs around the ring */
.glyph{
  position:absolute;
  font-size:16px;
  opacity:0.35;
  color:#c084fc;
}

/* center logo */
.logo{
  position:absolute;
  inset:0;
  display:flex;
  align-items:center;
  justify-content:center;
  flex-direction:column;
}
.logo-text{
  font-size:28px;
  font-weight:700;
  letter-spacing:-0.5px;
  background:linear-gradient(135deg,#a855f7,#ec4899);
  -webkit-background-clip:text;
  -webkit-text-fill-color:transparent;
  background-clip:text;
}
.logo-sub{
  font-size:11px;
  letter-spacing:3px;
  text-transform:uppercase;
  color:rgba(255,255,255,0.3);
  margin-top:2px;
}

/* message */
h1{
  font-size:20px;
  font-weight:600;
  margin-bottom:8px;
  color:rgba(255,255,255,0.92);
}
.msg{
  font-size:14px;
  color:rgba(255,255,255,0.45);
  line-height:1.6;
  max-width:280px;
  margin:0 auto;
}

/* pulse dots */
.dots{display:flex;gap:6px;justify-content:center;margin-top:24px}
.dot{
  width:6px;height:6px;border-radius:50%;
  background:#a855f7;
  animation:pulse 1.4s ease-in-out infinite;
}
.dot:nth-child(2){animation-delay:0.2s}
.dot:nth-child(3){animation-delay:0.4s}
@keyframes pulse{0%,80%,100%{opacity:0.2;transform:scale(0.8)}40%{opacity:1;transform:scale(1.1)}}

/* bottom */
.bottom{
  position:fixed;bottom:32px;left:0;right:0;
  text-align:center;
  font-size:11px;
  color:rgba(255,255,255,0.2);
}
</style>
</head>
<body>

<div class="stars" id="stars"></div>

<div>
  <div class="ring-wrap">
    <div class="ring"></div>
    <div class="logo">
      <div class="logo-text">big3.me</div>
      <div class="logo-sub">astro consul</div>
    </div>
  </div>

  <h1>Обновляемся</h1>
  <p class="msg">Звёзды перестраиваются — скоро всё заработает. Обычно это занимает пару минут.</p>

  <div class="dots">
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
  </div>
</div>

<div class="bottom">Страница обновится автоматически</div>

<script>
// generate star field
const c=document.getElementById('stars');
for(let i=0;i<80;i++){
  const s=document.createElement('div');
  s.className='star';
  s.style.left=Math.random()*100+'%';
  s.style.top=Math.random()*100+'%';
  s.style.setProperty('--d',(2+Math.random()*4).toFixed(1)+'s');
  s.style.setProperty('--o',(0.2+Math.random()*0.6).toFixed(2));
  s.style.animationDelay=(Math.random()*4).toFixed(1)+'s';
  c.appendChild(s);
}

// place zodiac glyphs around ring
const glyphs=["\\u2648","\\u2649","\\u264A","\\u264B","\\u264C","\\u264D","\\u264E","\\u264F","\\u2650","\\u2651","\\u2652","\\u2653"];
const ring=document.querySelector('.ring');
glyphs.forEach((g,i)=>{
  const el=document.createElement('span');
  el.className='glyph';
  el.textContent=g;
  const angle=(i*30-90)*Math.PI/180;
  const r=92;
  el.style.left=(100+r*Math.cos(angle)-8)+'px';
  el.style.top=(100+r*Math.sin(angle)-8)+'px';
  ring.appendChild(el);
});
</script>
</body>
</html>`;

export default {
  async fetch(request, env, ctx) {
    const response = await fetch(request);
    if (response.status === 502 || response.status === 503) {
      return new Response(MAINTENANCE_HTML, {
        status: 503,
        headers: {
          "Content-Type": "text/html;charset=UTF-8",
          "Retry-After": "30",
          "Cache-Control": "no-store",
        },
      });
    }
    return response;
  },
};
