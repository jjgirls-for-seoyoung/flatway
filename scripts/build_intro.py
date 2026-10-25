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
    "4f8fc0c69eaae37266bffe45665318b2": "map.jpg",
    "a2d023ddccf1dcf384b8ed54d55ff496": "filter_step.jpg",
    "92158119df7f857c27e7718cacfcb546": "tour1.jpg",
    "32c615140ca5bbccc30c588a13fea0ef": "tour2.jpg",
    "cbce4b9af33ab05318fe57bccd0a21f3": "tour3.jpg",
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
    page = page.replace("{{NOTES}}", json.dumps(notes, ensure_ascii=False))
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
html,body{margin:0;height:100%;background:#16251d;overflow:hidden;font-family:'Noto Sans KR','Malgun Gothic',sans-serif}
#view{position:fixed;left:0;top:0;right:0;bottom:56px;overflow:hidden}
#stage{position:absolute;left:0;top:0;width:1920px;height:1080px;transform-origin:0 0;background:#000}
.slide{position:absolute;left:0;top:0;width:1920px;height:1080px;overflow:hidden;opacity:0;pointer-events:none;transition:opacity .35s}
.slide.on{opacity:1;pointer-events:auto}
.slide p,.slide h1,.slide h2,.slide h3,.slide ul{margin:0}
.slide table{border-collapse:collapse}
.slide th,.slide td{padding:.35em .6em;text-align:left;border-bottom:1px solid #CFEBDD}
.slide th{font-weight:700;border-bottom:3px solid #2F5645}
.slide svg{display:block}
.slide img{display:block}
#bar{position:fixed;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;gap:10px;padding:0 14px;background:#0f1a14;color:#E0FBEF;font-size:15px}
#bar button{font:inherit;color:#E0FBEF;background:#24402F;border:0;border-radius:8px;padding:8px 14px;cursor:pointer}
#bar button:hover{background:#2F5645}
#prog{flex:1;height:6px;background:#24402F;border-radius:3px;overflow:hidden}
#prog i{display:block;height:100%;width:0;background:#3DD990;transition:width .3s}
#cnt{min-width:64px;text-align:center}
#ch{color:#8FE8BE;max-width:34vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#menu{position:fixed;left:14px;bottom:66px;max-height:70vh;overflow:auto;background:#0f1a14;border:1px solid #2F5645;border-radius:12px;padding:8px;display:none;z-index:5;min-width:280px}
#menu.open{display:block}
#menu a{display:flex;gap:10px;padding:8px 12px;color:#E0FBEF;text-decoration:none;border-radius:8px;font-size:15px}
#menu a:hover,#menu a.cur{background:#24402F}
#menu a b{color:#3DD990;min-width:26px}
#menu .h{color:#8FE8BE;font-size:13px;padding:10px 12px 4px}
#notes{position:fixed;left:0;right:0;bottom:56px;background:rgba(15,26,20,.94);color:#E0FBEF;padding:14px 22px;font-size:18px;line-height:1.6;display:none;z-index:4}
#notes.open{display:block}
@media (max-width:640px){#ch{display:none}}
</style>
</head>
<body>
<div id="view"><div id="stage">
{{SLIDES}}
</div></div>
<div id="notes"></div>
<div id="menu"></div>
<div id="bar">
<button id="mb" title="목차 (M)">목차</button>
<button id="pv" title="이전 (←)">◀</button>
<button id="nx" title="다음 (→)">▶</button>
<span id="cnt">1 / 20</span>
<div id="prog"><i></i></div>
<span id="ch"></span>
<button id="nb" title="발표 메모 (N)">메모</button>
<button id="fb" title="전체화면 (F)">전체화면</button>
</div>
<script>
var T={{TITLES}},NOTES={{NOTES}},CH={{CHAPTERS}};
var slides=[].slice.call(document.querySelectorAll('.slide')),n=slides.length,cur=-1;
var stage=document.getElementById('stage'),view=document.getElementById('view');
function fit(){var w=view.clientWidth,h=view.clientHeight,s=Math.min(w/1920,h/1080);stage.style.transform='scale('+s+')';stage.style.left=((w-1920*s)/2)+'px';stage.style.top=((h-1080*s)/2)+'px'}
function chapterOf(i){var c=CH[0];for(var k=0;k<CH.length;k++)if(CH[k].start<=i)c=CH[k];return c.label}
function mount(i,on){var fr=slides[i].querySelectorAll('iframe.embed');for(var k=0;k<fr.length;k++){if(on){if(!fr[k].getAttribute('srcdoc'))fr[k].setAttribute('srcdoc',fr[k].getAttribute('data-srcdoc'))}else fr[k].removeAttribute('srcdoc')}}
function go(i,noHash){i=Math.max(0,Math.min(n-1,i));if(i===cur)return;if(cur>=0){slides[cur].classList.remove('on');mount(cur,false)}cur=i;slides[i].classList.add('on');mount(i,true);
document.getElementById('cnt').textContent=(i+1)+' / '+n;document.querySelector('#prog i').style.width=((i+1)/n*100)+'%';document.getElementById('ch').textContent=chapterOf(i);
document.getElementById('notes').textContent=NOTES[i]||'';var cs=document.querySelectorAll('#menu a');for(var k=0;k<cs.length;k++)cs[k].classList.toggle('cur',k===i);
if(!noHash)history.replaceState(null,'','#'+(i+1))}
var mn=document.getElementById('menu'),hh='';CH.forEach(function(c,ci){});
(function(){var html='',ci=0;for(var i=0;i<n;i++){while(ci<CH.length&&CH[ci].start===i){html+='<div class="h">'+CH[ci].label+'</div>';ci++}html+='<a href="#'+(i+1)+'" data-i="'+i+'"><b>'+(i+1)+'</b>'+T[i]+'</a>'}mn.innerHTML=html})();
mn.addEventListener('click',function(e){var a=e.target.closest('a');if(a){e.preventDefault();go(+a.getAttribute('data-i'));mn.classList.remove('open')}});
document.getElementById('mb').onclick=function(){mn.classList.toggle('open')};
document.getElementById('pv').onclick=function(){go(cur-1)};document.getElementById('nx').onclick=function(){go(cur+1)};
document.getElementById('nb').onclick=function(){document.getElementById('notes').classList.toggle('open')};
function fs(){var d=document.documentElement;if(document.fullscreenElement)document.exitFullscreen();else if(d.requestFullscreen)d.requestFullscreen()}
document.getElementById('fb').onclick=fs;
document.addEventListener('keydown',function(e){var k=e.key;if(k==='ArrowRight'||k==='PageDown'||k===' '||k==='Enter'){go(cur+1);e.preventDefault()}else if(k==='ArrowLeft'||k==='PageUp'||k==='Backspace'){go(cur-1);e.preventDefault()}else if(k==='Home')go(0);else if(k==='End')go(n-1);else if(k==='f'||k==='F')fs();else if(k==='n'||k==='N')document.getElementById('notes').classList.toggle('open');else if(k==='m'||k==='M')mn.classList.toggle('open');else if(k==='Escape')mn.classList.remove('open')});
var sx=null;view.addEventListener('touchstart',function(e){sx=e.touches[0].clientX},{passive:true});view.addEventListener('touchend',function(e){if(sx===null)return;var dx=e.changedTouches[0].clientX-sx;if(Math.abs(dx)>50)go(cur+(dx<0?1:-1));sx=null});
view.addEventListener('click',function(e){mn.classList.remove('open');var r=view.getBoundingClientRect();if(e.clientX-r.left>r.width*0.5)go(cur+1);else go(cur-1)});
window.addEventListener('resize',fit);window.addEventListener('hashchange',function(){var h=parseInt(location.hash.slice(1),10);if(h)go(h-1,true)});
fit();var h0=parseInt(location.hash.slice(1),10);go(h0?h0-1:0,!h0);
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
