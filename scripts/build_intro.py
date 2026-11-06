"""발표 슬라이드(docs/intro-deck)를 서비스 안의 소개 페이지(flatway_app/web/intro/index.html)로 만든다.

슬라이드 원본은 Claude Slides 아티팩트와 같은 형식(고정 1920x1080, 인라인 스타일)이다.
이 스크립트는 그 원본을 한 장씩 보여 주는 독립 HTML 페이지로 감싼다.

    python scripts/build_intro.py
"""
import html
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECK = ROOT / "docs" / "intro-deck"
OUT = ROOT / "flatway_app" / "web" / "intro"

# 아티팩트에 올린 이미지 id -> 저장소 안의 파일 이름
BLOBS = {
    "6d1f0c8e4a2b47d9a3c5e7f81b2d4a60": "dash_pin.jpg",
    "9b3e5a7c1d2f48e6b0a4c6d8e1f3a572": "dash_heat.jpg",
    "4f8fc0c69eaae37266bffe45665318b2": "map.jpg",
    "a2d023ddccf1dcf384b8ed54d55ff496": "filter_step.jpg",
    "92158119df7f857c27e7718cacfcb546": "tour1.jpg",
    "32c615140ca5bbccc30c588a13fea0ef": "tour2.jpg",
    "cbce4b9af33ab05318fe57bccd0a21f3": "tour3.jpg",
    "eb6f0f83cf83c192a3fac23bf37f7342": "app_route.jpg",
    "a9e6ddb421ffba65840f7ade6654a5fb": "naver_route.jpg",
    "7e4767894b864bb51c0ded6ae89a2876": "route_ped.jpg",
    "78626c58b8e08b966f922b860288a8ff": "route_elec.jpg",
    "a05cdeb336bd63736a4af6f822a8c88b": "route_manual.jpg",
    "c11167c948022bd43d7968f5f6d3619e": "pair_ped.jpg",
    "91d8082b0b677757d95c6c56b5a1ebdd": "pair_elec.jpg",
    "5c956e3ab7fd30112220524ce9cd3d2d": "pair_manual.jpg",
    "d865df80eb220e8c196b8fb9bcf0dbd1": "same_manual.jpg",
}

EMBED_RE = re.compile(r'<x-embed style="([^"]*)">(.*?)</x-embed>', re.S)
ASIDE_RE = re.compile(r"<aside>(.*?)</aside>", re.S)
TITLE_RE = re.compile(r"<h[12][^>]*>(.*?)</h[12]>", re.S)


def convert_slide(src: str):
    notes = ""
    m = ASIDE_RE.search(src)
    if m:
        notes = m.group(1).strip()
        src = ASIDE_RE.sub("", src)

    def embed(match):
        style, body = match.group(1), match.group(2)
        doc = '<!doctype html><meta charset="utf-8">' + body
        return (
            f'<iframe class="embed" sandbox="allow-scripts" title="모션 그래픽" '
            f'style="{style};border:0;background:transparent" '
            f'data-srcdoc="{html.escape(doc, quote=True)}"></iframe>'
        )

    src = EMBED_RE.sub(embed, src)
    for blob_id, name in BLOBS.items():
        src = src.replace(f"/_blob/{blob_id}", f"img/{name}")
    src = src.replace("<section ", '<section class="slide" ', 1)
    return src, notes


def main():
    deck = json.loads((DECK / "deck.json").read_text(encoding="utf-8"))
    slides, notes, titles = [], [], []
    for sid in deck["order"]:
        src = (DECK / "slides" / f"{sid}.html").read_text(encoding="utf-8")
        title = TITLE_RE.search(src)
        titles.append(re.sub(r"<[^>]+>", "", title.group(1)).strip() if title else sid)
        body, note = convert_slide(src)
        slides.append(body)
        notes.append(note)

    chapters = []
    for key, sec in deck["sections"].items():
        chapters.append({"label": sec["description"].split(":")[0], "start": deck["order"].index(sec["start"])})

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "img").mkdir(exist_ok=True)
    for f in (DECK / "img").glob("*.jpg"):
        shutil.copy2(f, OUT / "img" / f.name)

    page = TEMPLATE.replace("{{SLIDES}}", "\n".join(slides))
    page = page.replace("{{TITLES}}", json.dumps(titles, ensure_ascii=False))
    page = page.replace("{{CHAPTERS}}", json.dumps(chapters, ensure_ascii=False))
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(f"slides={len(slides)} -> {OUT / 'index.html'} ({len(page) // 1024} KB)")


TEMPLATE = r"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>FlatWay 소개</title>
<link rel="icon" href="../favicon.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Black+Han+Sans&family=Noto+Sans+KR:wght@400;500;700&display=swap">
<style>
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:#f3f4f6;overflow:hidden;font-family:'Noto Sans KR','Malgun Gothic',sans-serif}
#view{position:fixed;left:0;top:0;right:0;bottom:64px;overflow:hidden}
html:fullscreen #view{background:#111}
#stage{position:absolute;left:0;top:0;width:1920px;height:1080px;transform-origin:0 0;background:#fff;box-shadow:0 0 0 1px rgba(0,0,0,.06),0 8px 32px rgba(0,0,0,.14)}
.slide{position:absolute;left:0;top:0;width:1920px;height:1080px;overflow:hidden;opacity:0;pointer-events:none;transition:opacity .35s;word-break:keep-all}
.slide.on{opacity:1;pointer-events:auto}
.slide p,.slide h1,.slide h2,.slide h3,.slide ul{margin:0}
.slide table{border-collapse:collapse}
.slide th,.slide td{padding:.35em .6em;text-align:left;border-bottom:1px solid #CFEBDD}
.slide th{font-weight:700;border-bottom:3px solid #2F5645}
.slide svg{display:block}
.slide img{display:block}
.slide .rise,.slide .pop,.slide .slide-r,.slide .fadein,.slide .draw,.slide .wipe{opacity:0}
.slide .draw{stroke-dasharray:1;stroke-dashoffset:1}
.slide.on .rise{animation:rise .5s cubic-bezier(.23,1,.32,1) both;animation-delay:calc(var(--d,0s)*.5)}
.slide.on .slide-r{animation:slider .5s cubic-bezier(.23,1,.32,1) both;animation-delay:calc(var(--d,0s)*.5)}
.slide.on .fadein{animation:fadein .9s ease both;animation-delay:calc(var(--d,0s)*.5)}
.slide.on .pop{animation:pop .4s cubic-bezier(.23,1,.32,1) both;animation-delay:calc(var(--d,0s)*.5)}
.slide.on .draw{animation:draw 1s cubic-bezier(.23,1,.32,1) both;animation-delay:calc(var(--d,0s)*.5)}
.slide.on .wipe{animation:wipe 1s cubic-bezier(.23,1,.32,1) both;animation-delay:calc(var(--d,0s)*.5)}
.slide .pop{transform-box:fill-box;transform-origin:center}
@keyframes rise{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:none}}
@keyframes slider{from{opacity:0;transform:translateX(32px)}to{opacity:1;transform:none}}
@keyframes fadein{from{opacity:0}to{opacity:1}}
@keyframes pop{from{opacity:0;transform:scale(.92)}to{opacity:1;transform:scale(1)}}
@keyframes draw{from{opacity:1;stroke-dashoffset:1}to{opacity:1;stroke-dashoffset:0}}
@keyframes wipe{from{opacity:1;clip-path:inset(0 100% 0 0)}to{opacity:1;clip-path:inset(0 0 0 0)}}
.slide.on .nudge{animation:nudge 1.2s cubic-bezier(.45,0,.55,1) 1.6s 3 both}
@keyframes nudge{0%,100%{transform:translateX(-6px)}50%{transform:translateX(12px)}}
.slide.on .pkt1{animation:pkt1 4.4s cubic-bezier(.45,0,.2,1) .8s 3 both}
.slide.on .pkt2{animation:pkt2 4.4s cubic-bezier(.45,0,.2,1) .8s 3 both}
.slide.on .dbpulse{animation:dbp 4.4s ease-out .8s 3}
.slide.on .pinpop{animation:pinp 4.4s cubic-bezier(.3,1.4,.5,1) .8s 3 both}
.slide .dbpulse,.slide .pinpop{transform-box:fill-box;transform-origin:center}
@keyframes pkt1{0%{transform:translateX(0);opacity:0}6%{opacity:1}34%{transform:translateX(372px);opacity:1}38%,100%{transform:translateX(372px);opacity:0}}
@keyframes pkt2{0%,40%{transform:translateX(0);opacity:0}46%{opacity:1}74%{transform:translateX(372px);opacity:1}78%,100%{transform:translateX(372px);opacity:0}}
@keyframes dbp{0%,32%{transform:scale(1)}38%{transform:scale(1.09)}48%,100%{transform:scale(1)}}
@keyframes pinp{0%,74%{opacity:0;transform:scale(.3)}82%{opacity:1;transform:scale(1.2)}90%,100%{opacity:1;transform:scale(1)}}
@media (prefers-reduced-motion:reduce){@keyframes rise{from{opacity:0}to{opacity:1}}@keyframes slider{from{opacity:0}to{opacity:1}}@keyframes pop{from{opacity:0}to{opacity:1}}}
#bar{position:fixed;left:0;right:0;bottom:0;height:64px;display:flex;align-items:center;gap:8px;padding:0 16px;background:#fff;border-top:1px solid #e5e7eb;color:#374151;font-size:14px}
#bar button{font:inherit;font-weight:500;color:#374151;background:#fff;border:1px solid #d1d5db;border-radius:10px;padding:9px 14px;cursor:pointer;white-space:nowrap;transition:background .15s,border-color .15s}
#bar button:hover:not(:disabled){background:#f3f4f6;border-color:#9ca3af}
#bar button:focus-visible{outline:2px solid #047857;outline-offset:2px}
#bar button:disabled{color:#c4c8cf;border-color:#eceef1;cursor:default}
#bar button.pri{background:#047857;border-color:#047857;color:#fff}
#bar button.pri:hover:not(:disabled){background:#065f46;border-color:#065f46}
#bar button.pri:disabled{background:#e5e7eb;border-color:#e5e7eb;color:#9ca3af}
#bar .sp{width:8px}
#prog{flex:1;height:6px;background:#e5e7eb;border-radius:3px;overflow:hidden;min-width:40px}
#prog i{display:block;height:100%;width:0;background:#047857;transition:width .3s}
#cnt{min-width:64px;text-align:center;font-weight:700;color:#111827}
#ch{color:#6b7280;max-width:30vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#menu{position:fixed;left:16px;bottom:74px;max-height:70vh;overflow:auto;background:#fff;border:1px solid #e5e7eb;border-radius:14px;padding:8px;display:none;z-index:5;min-width:300px;box-shadow:0 12px 32px rgba(0,0,0,.14)}
#menu.open{display:block}
#menu a{display:flex;gap:12px;padding:9px 12px;color:#374151;text-decoration:none;border-radius:8px;font-size:14px}
#menu a:hover{background:#f3f4f6}
#menu a.cur{background:#ecfdf5;color:#065f46;font-weight:700}
#menu a b{color:#6b7280;min-width:26px;font-weight:500}
#menu a.cur b{color:#047857}
#menu .h{color:#6b7280;font-size:12px;font-weight:700;padding:12px 12px 4px}
@media (max-width:640px){#ch{display:none}#bar{gap:6px;padding:0 10px}#bar button{padding:9px 11px}#bar .t{display:none}#cnt{min-width:52px}}
</style>
</head>
<body>
<div id="view"><div id="stage">
{{SLIDES}}
</div></div>
<div id="menu"></div>
<div id="bar">
<button id="hm" title="처음으로 (Home)" aria-label="처음으로">⏮<span class="t"> 처음으로</span></button>
<button id="mb" title="목차 (M)" aria-label="목차">☰<span class="t"> 목차</span></button>
<span class="sp"></span>
<button id="pv" title="이전 (←)" aria-label="이전 슬라이드">←<span class="t"> 이전</span></button>
<button id="nx" class="pri" title="다음 (→)" aria-label="다음 슬라이드"><span class="t">다음 </span>→</button>
<span id="cnt">1 / 20</span>
<div id="prog"><i></i></div>
<span id="ch"></span>
<button id="fb" title="전체화면 (F)" aria-label="전체화면">⛶<span class="t"> 전체화면</span></button>
</div>
<script>
var T={{TITLES}},CH={{CHAPTERS}};
var slides=[].slice.call(document.querySelectorAll('.slide')),n=slides.length,cur=-1;
var stage=document.getElementById('stage'),view=document.getElementById('view');
function fit(){var w=view.clientWidth,h=view.clientHeight,s=Math.min(w/1920,h/1080);stage.style.transform='scale('+s+')';stage.style.left=((w-1920*s)/2)+'px';stage.style.top=((h-1080*s)/2)+'px'}
function chapterOf(i){var c=CH[0];for(var k=0;k<CH.length;k++)if(CH[k].start<=i)c=CH[k];return c.label}
function mount(i,on){var fr=slides[i].querySelectorAll('iframe.embed');for(var k=0;k<fr.length;k++){if(on){if(!fr[k].getAttribute('srcdoc'))fr[k].setAttribute('srcdoc',fr[k].getAttribute('data-srcdoc'))}else fr[k].removeAttribute('srcdoc')}}
function countUp(s){var els=s.querySelectorAll('[data-count]');for(var k=0;k<els.length;k++)(function(e){var to=+e.getAttribute('data-count'),suf=e.getAttribute('data-suffix')||'',t0=performance.now();(function f(t){var p=Math.min(1,(t-t0)/1100);e.textContent=Math.round(to*(1-Math.pow(1-p,3)))+suf;if(p<1)requestAnimationFrame(f)})(t0)})(els[k])}
function go(i,noHash){i=Math.max(0,Math.min(n-1,i));if(i===cur)return;if(cur>=0){slides[cur].classList.remove('on');mount(cur,false)}cur=i;slides[i].classList.add('on');mount(i,true);countUp(slides[i]);
document.getElementById('cnt').textContent=(i+1)+' / '+n;document.getElementById('hm').disabled=document.getElementById('pv').disabled=(i===0);document.getElementById('nx').disabled=(i===n-1);document.querySelector('#prog i').style.width=((i+1)/n*100)+'%';document.getElementById('ch').textContent=chapterOf(i);
var cs=document.querySelectorAll('#menu a');for(var k=0;k<cs.length;k++)cs[k].classList.toggle('cur',k===i);
if(!noHash)history.replaceState(null,'','#'+(i+1))}
var mn=document.getElementById('menu'),hh='';CH.forEach(function(c,ci){});
(function(){var html='',ci=0;for(var i=0;i<n;i++){while(ci<CH.length&&CH[ci].start===i){html+='<div class="h">'+CH[ci].label+'</div>';ci++}html+='<a href="#'+(i+1)+'" data-i="'+i+'"><b>'+(i+1)+'</b>'+T[i]+'</a>'}mn.innerHTML=html})();
mn.addEventListener('click',function(e){var a=e.target.closest('a');if(a){e.preventDefault();go(+a.getAttribute('data-i'));mn.classList.remove('open')}});
document.getElementById('mb').onclick=function(){mn.classList.toggle('open')};
document.getElementById('hm').onclick=function(){go(0);mn.classList.remove('open')};document.getElementById('pv').onclick=function(){go(cur-1)};document.getElementById('nx').onclick=function(){go(cur+1)};
function fs(){var d=document.documentElement;if(document.fullscreenElement)document.exitFullscreen();else if(d.requestFullscreen)d.requestFullscreen()}
document.getElementById('fb').onclick=fs;
document.addEventListener('keydown',function(e){var k=e.key;if(k==='ArrowRight'||k==='PageDown'||k===' '||k==='Enter'){go(cur+1);e.preventDefault()}else if(k==='ArrowLeft'||k==='PageUp'||k==='Backspace'){go(cur-1);e.preventDefault()}else if(k==='Home')go(0);else if(k==='End')go(n-1);else if(k==='f'||k==='F')fs();else if(k==='m'||k==='M')mn.classList.toggle('open');else if(k==='Escape')mn.classList.remove('open')});
var sx=null;view.addEventListener('touchstart',function(e){sx=e.touches[0].clientX},{passive:true});view.addEventListener('touchend',function(e){if(sx===null)return;var dx=e.changedTouches[0].clientX-sx;if(Math.abs(dx)>50)go(cur+(dx<0?1:-1));sx=null});
view.addEventListener('click',function(e){mn.classList.remove('open');var r=view.getBoundingClientRect();if(e.clientX-r.left>r.width*0.5)go(cur+1);else go(cur-1)});
window.addEventListener('resize',fit);window.addEventListener('hashchange',function(){var h=parseInt(location.hash.slice(1),10);if(h)go(h-1,true)});
document.getElementById('bar').addEventListener('click',function(e){var b=e.target.closest('button');if(b)b.blur()});
fit();var h0=parseInt(location.hash.slice(1),10);go(h0?h0-1:0,!h0);
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
