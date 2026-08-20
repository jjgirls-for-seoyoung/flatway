import os
from PIL import Image, ImageDraw, ImageFont

os.makedirs('assets', exist_ok=True)

FONT_REG = 'C:/Windows/Fonts/malgun.ttf'
FONT_BOLD = 'C:/Windows/Fonts/malgunbd.ttf'

def get_font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    except Exception:
        return ImageFont.load_default()

# MongoDB Design Tokens
C_BRAND_GREEN = "#00ED64"
C_BRAND_GREEN_DARK = "#00684A"
C_BRAND_GREEN_SOFT = "#C3F0D2"
C_BRAND_TEAL_DEEP = "#001E2B"
C_BRAND_TEAL = "#003D4F"
C_ON_PRIMARY = "#001E2B"
C_ACCENT_ORANGE = "#FA6E39"
C_ACCENT_PURPLE = "#7B3FF2"
C_ACCENT_BLUE = "#3D4F9F"
C_CANVAS = "#FFFFFF"
C_SURFACE = "#F9FBFA"
C_SURFACE_FEATURE = "#E3FCEF"
C_HAIRLINE = "#E1E5E8"
C_HAIRLINE_STRONG = "#C1CCD6"
C_HAIRLINE_DARK = "#1C2D38"
C_INK = "#001E2B"
C_CHARCOAL = "#1C2D38"
C_SLATE = "#3D4F5B"
C_STEEL = "#5C6C7A"
C_ON_DARK = "#FFFFFF"
C_ON_DARK_MUTED = "#A8B3BC"

def draw_phone_frame(draw, w, h):
    # Outer device bezel (MongoDB brand-teal-deep)
    draw.rounded_rectangle([10, 10, w - 10, h - 10], radius=44, fill=C_BRAND_TEAL_DEEP, outline=C_HAIRLINE_DARK, width=4)
    # Screen inner canvas
    draw.rounded_rectangle([20, 20, w - 20, h - 20], radius=36, fill=C_SURFACE)
    # Dynamic Island / Notch
    draw.rounded_rectangle([w // 2 - 70, 28, w // 2 + 70, 56], radius=14, fill="#000D12")
    # Status bar text
    f_stat = get_font(18, True)
    draw.text((45, 32), "09:41", font=f_stat, fill=C_INK)
    draw.text((w - 110, 32), "5G  98%", font=f_stat, fill=C_INK)

def draw_app_header(draw, w, title="FlatWay"):
    f_logo = get_font(25, True)
    # Header bar (MongoDB hero-band-dark)
    draw.rectangle([20, 68, w - 20, 126], fill=C_BRAND_TEAL_DEEP)
    # MongoDB Green Pill Badge for App Name
    draw.rounded_rectangle([36, 78, 128, 116], radius=19, fill=C_BRAND_GREEN)
    draw.text((82, 97), "FlatWay", font=get_font(17, True), fill=C_ON_PRIMARY, anchor="mm")
    
    draw.text((142, 84), title, font=f_logo, fill=C_ON_DARK)
    draw.text((142, 107), "이동 약자를 위한 배리어프리 지도", font=get_font(12, False), fill=C_ON_DARK_MUTED)
    
    # Menu button on right (pill outline)
    draw.rounded_rectangle([w - 65, 82, w - 35, 112], radius=15, fill=C_BRAND_TEAL, outline=C_HAIRLINE_DARK, width=1)
    draw.text((w - 50, 97), "≡", font=get_font(20, True), fill=C_BRAND_GREEN, anchor="mm")

def create_screen1():
    w, h = 600, 1200
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    draw_phone_frame(draw, w, h)
    draw_app_header(draw, w, "경로 검색")

    # Search Box Card (MongoDB card-base)
    draw.rounded_rectangle([35, 140, w - 35, 280], radius=16, fill=C_CANVAS, outline=C_HAIRLINE, width=2)
    
    # Origin field (MongoDB Green Pill)
    draw.rounded_rectangle([48, 153, 94, 183], radius=15, fill=C_BRAND_GREEN)
    draw.text((71, 168), "출발", font=get_font(13, True), fill=C_ON_PRIMARY, anchor="mm")
    draw.text((106, 157), "작전여자고등학교", font=get_font(18, True), fill=C_INK)
    draw.text((w - 75, 157), "[위치]", font=get_font(14, True), fill=C_STEEL)

    draw.line([48, 195, w - 48, 195], fill=C_HAIRLINE, width=1)

    # Destination field (MongoDB Accent Orange Pill)
    draw.rounded_rectangle([48, 207, 94, 237], radius=15, fill=C_ACCENT_ORANGE)
    draw.text((71, 222), "도착", font=get_font(13, True), fill=C_ON_DARK, anchor="mm")
    draw.text((106, 211), "작전역 (인천1호선)", font=get_font(18, True), fill=C_INK)
    draw.text((w - 75, 211), "[검색]", font=get_font(14, True), fill=C_BRAND_GREEN_DARK)

    # Current location badge (badge-green-soft)
    draw.rounded_rectangle([48, 246, 185, 273], radius=13, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN_SOFT, width=1)
    draw.text((116, 259), "● 내 현재 위치 기준", font=get_font(12, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    # Map area
    draw.rounded_rectangle([35, 295, w - 35, 930], radius=18, fill="#E8ECEF", outline=C_HAIRLINE, width=2)
    draw.rectangle([45, 305, w - 45, 920], fill="#E8ECEF")
    
    # Parks (Mint tints)
    draw.rounded_rectangle([60, 480, 240, 680], radius=12, fill=C_SURFACE_FEATURE)
    draw.text((150, 580), "[작전공원]", font=get_font(16, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.rounded_rectangle([320, 680, 520, 880], radius=12, fill=C_SURFACE_FEATURE)
    draw.text((420, 780), "[갈산근린공원]", font=get_font(16, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    # Roads
    draw.line([280, 310, 280, 915], fill=C_CANVAS, width=36)
    draw.line([280, 310, 280, 915], fill=C_HAIRLINE, width=2)

    draw.line([50, 450, w - 50, 450], fill=C_CANVAS, width=28)
    draw.line([50, 650, w - 50, 650], fill=C_CANVAS, width=32)
    draw.line([50, 850, w - 50, 850], fill=C_CANVAS, width=28)

    # Route line (MongoDB signature green)
    points = [(430, 370), (280, 370), (280, 650), (140, 650), (140, 820)]
    for i in range(len(points)-1):
        draw.line([points[i], points[i+1]], fill=C_BRAND_GREEN, width=12)

    # Start Pin
    draw.rounded_rectangle([350, 305, 520, 338], radius=8, fill=C_BRAND_TEAL_DEEP)
    draw.text((435, 321), "작전여자고등학교 (출발)", font=get_font(13, True), fill=C_BRAND_GREEN, anchor="mm")
    draw.ellipse([410, 345, 460, 395], fill=C_BRAND_GREEN, outline=C_CANVAS, width=3)
    draw.text((435, 370), "출발", font=get_font(14, True), fill=C_ON_PRIMARY, anchor="mm")

    # Destination Pin
    draw.rounded_rectangle([65, 855, 215, 888], radius=8, fill=C_BRAND_TEAL_DEEP)
    draw.text((140, 871), "작전역 2번출구 (도착)", font=get_font(13, True), fill=C_ON_DARK, anchor="mm")
    draw.ellipse([115, 795, 165, 845], fill=C_ACCENT_ORANGE, outline=C_CANVAS, width=3)
    draw.text((140, 820), "도착", font=get_font(14, True), fill=C_ON_DARK, anchor="mm")

    # Hazard Markers (MongoDB badge-orange / badge-green-soft)
    draw.rounded_rectangle([180, 410, 380, 442], radius=16, fill="#FFF8E0", outline=C_ACCENT_ORANGE, width=2)
    draw.text((280, 426), "[단차 주의] 보도턱 5cm", font=get_font(13, True), fill="#946F3F", anchor="mm")

    draw.rounded_rectangle([200, 560, 360, 592], radius=16, fill="#FEE2E2", outline=C_ACCENT_ORANGE, width=2)
    draw.text((280, 576), "[노면 파손] 블록 파손", font=get_font(13, True), fill="#991B1B", anchor="mm")

    draw.rounded_rectangle([75, 615, 240, 647], radius=16, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=2)
    draw.text((157, 631), "[완만 경사] 통행 수월", font=get_font(13, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    # Floating Bottom Report Card (MongoDB card-feature-dark)
    draw.rounded_rectangle([35, 945, w - 35, 1160], radius=20, fill=C_BRAND_TEAL_DEEP, outline=C_BRAND_TEAL, width=2)
    draw.rounded_rectangle([45, 955, w - 45, 1015], radius=14, fill=C_BRAND_TEAL)
    draw.text((w // 2, 985), "[실시간 제보] 도로 단차 및 노면 파손 등록", font=get_font(17, True), fill=C_BRAND_GREEN, anchor="mm")

    draw.text((55, 1030), "• 보행 중 발견한 턱이나 파손 도로를 사진과 함께 등록하세요.", font=get_font(14, False), fill=C_ON_DARK)
    draw.text((55, 1058), "• 제보된 위치는 즉시 검증 후 다른 사용자 지도에 실시간 공유됩니다.", font=get_font(13, False), fill=C_ON_DARK_MUTED)

    # MongoDB Pill Buttons
    draw.rounded_rectangle([55, 1095, 270, 1145], radius=25, fill=None, outline=C_BRAND_GREEN, width=2)
    draw.text((162, 1120), "사진으로 제보", font=get_font(15, True), fill=C_BRAND_GREEN, anchor="mm")

    draw.rounded_rectangle([285, 1095, 500, 1145], radius=25, fill=C_BRAND_GREEN)
    draw.text((392, 1120), "경로 탐색 시작 ▶", font=get_font(15, True), fill=C_ON_PRIMARY, anchor="mm")

    img.save("assets/mockup_screen1.png")
    print("MongoDB-styled Screen 1 updated")

def create_screen2():
    w, h = 600, 1200
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    draw_phone_frame(draw, w, h)
    draw_app_header(draw, w, "이동 수단 선택")

    # Step indicator
    draw.text((40, 140), "STEP 2", font=get_font(14, True), fill=C_BRAND_GREEN_DARK)
    draw.text((40, 160), "맞춤형 이동 수단을 선택해 주세요", font=get_font(22, True), fill=C_INK)
    draw.text((40, 192), "수단별 주행 특성과 도로 상태에 최적화된 경로를 안내합니다.", font=get_font(14, False), fill=C_STEEL)

    # Card 1: 일반 보행자 모드 (MongoDB card-base)
    draw.rounded_rectangle([35, 230, w - 35, 470], radius=16, fill=C_CANVAS, outline=C_HAIRLINE, width=2)
    draw.rounded_rectangle([55, 248, 125, 308], radius=12, fill=C_SURFACE)
    draw.text((90, 278), "보행자", font=get_font(15, True), fill=C_STEEL, anchor="mm")
    draw.text((140, 250), "일반 보행자 모드", font=get_font(20, True), fill=C_INK)
    draw.text((140, 280), "도보 기준 최단거리 및 횡단보도 우선 안내", font=get_font(14, False), fill=C_STEEL)

    draw.rounded_rectangle([55, 330, 185, 380], radius=8, fill=C_SURFACE)
    draw.text((120, 343), "거리", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((120, 362), "약 873m", font=get_font(16, True), fill=C_INK, anchor="mm")

    draw.rounded_rectangle([200, 330, 330, 380], radius=8, fill=C_SURFACE)
    draw.text((265, 343), "예상 시간", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((265, 362), "약 12분", font=get_font(16, True), fill=C_INK, anchor="mm")

    draw.rounded_rectangle([345, 330, 475, 380], radius=8, fill=C_SURFACE)
    draw.text((410, 343), "추천 경로", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((410, 362), "3개 경로", font=get_font(16, True), fill=C_INK, anchor="mm")

    # Secondary Button
    draw.rounded_rectangle([55, 400, w - 55, 450], radius=25, fill=None, outline=C_HAIRLINE_STRONG, width=1)
    draw.text((w // 2, 425), "선택하기", font=get_font(16, True), fill=C_INK, anchor="mm")

    # Card 2: 전동 휠체어 모드 (MongoDB pricing-card-featured Style: Mint bg + Green border)
    draw.rounded_rectangle([35, 490, w - 35, 770], radius=16, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=3)
    
    # Recommended Badge (badge-popular style: dark teal pill with green text)
    draw.rounded_rectangle([w - 145, 505, w - 50, 535], radius=15, fill=C_BRAND_TEAL_DEEP)
    draw.text((w - 97, 520), "★ 맞춤 추천", font=get_font(13, True), fill=C_BRAND_GREEN, anchor="mm")

    draw.rounded_rectangle([55, 508, 125, 568], radius=12, fill=C_BRAND_GREEN_SOFT)
    draw.text((90, 538), "전동", font=get_font(18, True), fill=C_BRAND_GREEN_DARK, anchor="mm")
    draw.text((140, 510), "전동 휠체어 모드", font=get_font(20, True), fill=C_BRAND_GREEN_DARK)
    draw.text((140, 540), "고속 주행 안정성 & 노면 진동/턱 회피 특화", font=get_font(14, True), fill=C_INK)

    draw.rounded_rectangle([55, 590, 185, 650], radius=8, fill=C_CANVAS, outline=C_BRAND_GREEN_SOFT, width=1)
    draw.text((120, 606), "거리", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((120, 628), "약 897m", font=get_font(17, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.rounded_rectangle([200, 590, 330, 650], radius=8, fill=C_CANVAS, outline=C_BRAND_GREEN_SOFT, width=1)
    draw.text((265, 606), "예상 시간", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((265, 628), "약 7분", font=get_font(17, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.rounded_rectangle([345, 590, 475, 650], radius=8, fill=C_CANVAS, outline=C_BRAND_GREEN_SOFT, width=1)
    draw.text((410, 606), "노면 안전도", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((410, 628), "안전 99%", font=get_font(17, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.text((55, 665), "• 단차 3cm 이상 도로 자동 우회", font=get_font(13, True), fill=C_BRAND_GREEN_DARK)
    draw.text((270, 665), "• 엘리베이터 설치 출입구 직결", font=get_font(13, True), fill=C_BRAND_GREEN_DARK)

    # Primary Pill CTA (button-primary)
    draw.rounded_rectangle([55, 700, w - 55, 750], radius=25, fill=C_BRAND_GREEN)
    draw.text((w // 2, 725), "✓ 선택 완료 (다음으로)", font=get_font(16, True), fill=C_ON_PRIMARY, anchor="mm")

    # Card 3: 수동 휠체어 모드 (MongoDB card-base)
    draw.rounded_rectangle([35, 790, w - 35, 1030], radius=16, fill=C_CANVAS, outline=C_HAIRLINE, width=2)
    draw.rounded_rectangle([55, 808, 125, 868], radius=12, fill="#FAF5FF")
    draw.text((90, 838), "수동", font=get_font(18, True), fill=C_ACCENT_PURPLE, anchor="mm")
    draw.text((140, 810), "수동 휠체어 모드", font=get_font(20, True), fill=C_INK)
    draw.text((140, 840), "체력 소모 최소화: 급경사 배제 및 완만 경사 우선", font=get_font(14, False), fill=C_STEEL)

    draw.rounded_rectangle([55, 890, 185, 940], radius=8, fill=C_SURFACE)
    draw.text((120, 903), "거리", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((120, 922), "약 898m", font=get_font(16, True), fill=C_INK, anchor="mm")

    draw.rounded_rectangle([200, 890, 330, 940], radius=8, fill=C_SURFACE)
    draw.text((265, 903), "예상 시간", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((265, 922), "약 18분", font=get_font(16, True), fill=C_INK, anchor="mm")

    draw.rounded_rectangle([345, 890, 475, 940], radius=8, fill=C_SURFACE)
    draw.text((410, 903), "최대 경사도", font=get_font(12, False), fill=C_STEEL, anchor="mm")
    draw.text((410, 922), "최대 2.8°", font=get_font(16, True), fill=C_INK, anchor="mm")

    draw.rounded_rectangle([55, 960, w - 55, 1010], radius=25, fill=None, outline=C_HAIRLINE_STRONG, width=1)
    draw.text((w // 2, 985), "선택하기", font=get_font(16, True), fill=C_INK, anchor="mm")

    # Bottom summary tip (MongoDB why-card)
    draw.rounded_rectangle([35, 1050, w - 35, 1160], radius=14, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN_SOFT, width=1)
    draw.text((50, 1065), "[알고리즘] FlatWay 지능형 경로 탐색", font=get_font(15, True), fill=C_BRAND_GREEN_DARK)
    draw.text((50, 1095), "센서로 수집된 노면 진동·단차 데이터와 지도 경사도 데이터를", font=get_font(13, False), fill=C_INK)
    draw.text((50, 1120), "결합하여 탑승자에게 가장 신체적 부담이 적은 길을 찾아줍니다.", font=get_font(13, False), fill=C_INK)

    img.save("assets/mockup_screen2.png")
    print("MongoDB-styled Screen 2 updated")

def create_screen3():
    w, h = 600, 1200
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    draw_phone_frame(draw, w, h)
    draw_app_header(draw, w, "맞춤 경로 안내")

    # Map background
    draw.rectangle([20, 126, w - 20, 680], fill="#E8ECEF")

    # Parks
    draw.rounded_rectangle([30, 150, 200, 320], radius=12, fill=C_SURFACE_FEATURE)
    draw.text((115, 235), "[작전공원]", font=get_font(15, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.rounded_rectangle([350, 420, 570, 640], radius=12, fill=C_SURFACE_FEATURE)
    draw.text((460, 530), "[갈산근린공원]", font=get_font(15, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    # Roads
    draw.line([280, 130, 280, 680], fill=C_CANVAS, width=36)
    draw.line([280, 130, 280, 680], fill=C_HAIRLINE, width=2)
    draw.line([30, 280, 570, 280], fill=C_CANVAS, width=28)
    draw.line([30, 460, 570, 460], fill=C_CANVAS, width=34)

    # Route 1: Main Route (MongoDB Green)
    r1_points = [(450, 200), (280, 200), (280, 460), (140, 460), (140, 620)]
    for i in range(len(r1_points)-1):
        draw.line([r1_points[i], r1_points[i+1]], fill=C_BRAND_GREEN, width=14)

    # Route 2: Accent Purple
    r2_points = [(450, 200), (450, 380), (280, 380), (140, 380), (140, 620)]
    for i in range(len(r2_points)-1):
        draw.line([r2_points[i], r2_points[i+1]], fill=C_ACCENT_PURPLE, width=8)

    # Route 3: Charcoal hairline
    draw.line([(450, 200), (280, 280)], fill=C_STEEL, width=6)
    draw.line([(280, 280), (140, 620)], fill=C_STEEL, width=6)

    # Pins
    draw.rounded_rectangle([350, 138, 520, 168], radius=8, fill=C_BRAND_TEAL_DEEP)
    draw.text((435, 153), "작전여고 (출발)", font=get_font(12, True), fill=C_BRAND_GREEN, anchor="mm")
    draw.ellipse([430, 175, 475, 220], fill=C_BRAND_GREEN, outline=C_CANVAS, width=3)
    draw.text((452, 197), "출발", font=get_font(13, True), fill=C_ON_PRIMARY, anchor="mm")

    draw.rounded_rectangle([50, 648, 230, 678], radius=8, fill=C_BRAND_TEAL_DEEP)
    draw.text((140, 663), "작전역 (승강기 완비)", font=get_font(12, True), fill=C_ON_DARK, anchor="mm")
    draw.ellipse([115, 595, 165, 645], fill=C_ACCENT_ORANGE, outline=C_CANVAS, width=3)
    draw.text((140, 620), "도착", font=get_font(13, True), fill=C_ON_DARK, anchor="mm")

    # Accessibility Badges
    draw.rounded_rectangle([180, 240, 380, 270], radius=15, fill="#FFF8E0", outline=C_ACCENT_ORANGE, width=2)
    draw.text((280, 255), "[일반경로] 턱 7cm 주의", font=get_font(12, True), fill="#946F3F", anchor="mm")

    draw.rounded_rectangle([180, 420, 380, 450], radius=15, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=2)
    draw.text((280, 435), "[추천경로] 평탄 보행로", font=get_font(12, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    # Bottom Sheet (MongoDB card-feature-dark)
    draw.rounded_rectangle([25, 690, w - 25, 1170], radius=24, fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    # Route Option 1 (Selected - MongoDB pricing-card-featured style)
    draw.rounded_rectangle([40, 710, w - 40, 830], radius=14, fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=2)
    draw.rounded_rectangle([55, 725, 155, 755], radius=15, fill=C_BRAND_GREEN)
    draw.text((105, 740), "추천 경로 1", font=get_font(13, True), fill=C_ON_PRIMARY, anchor="mm")
    draw.text((170, 727), "가장 파손 적은 안심길", font=get_font(18, True), fill=C_INK)
    draw.text((55, 765), "약 897m  |  7분 소요  |  노면 평탄도 98%  |  단차 0건 우회", font=get_font(14, True), fill=C_BRAND_GREEN_DARK)
    draw.rounded_rectangle([w - 110, 745, w - 55, 795], radius=25, fill=C_BRAND_GREEN)
    draw.text((w - 82, 770), "선택됨", font=get_font(13, True), fill=C_ON_PRIMARY, anchor="mm")

    # Route Option 2 (MongoDB Accent Purple Tag)
    draw.rounded_rectangle([40, 845, w - 40, 945], radius=14, fill=C_CANVAS, outline=C_HAIRLINE, width=1)
    draw.rounded_rectangle([55, 860, 155, 890], radius=15, fill=C_ACCENT_PURPLE)
    draw.text((105, 875), "대안 경로 2", font=get_font(13, True), fill=C_ON_DARK, anchor="mm")
    draw.text((170, 862), "가장 단차 적은 평탄길", font=get_font(17, True), fill=C_INK)
    draw.text((55, 900), "약 915m  |  8분 소요  |  완만 경사로 우선", font=get_font(14, False), fill=C_STEEL)
    draw.rounded_rectangle([w - 110, 870, w - 55, 920], radius=25, fill=None, outline=C_HAIRLINE_STRONG, width=1)
    draw.text((w - 82, 895), "선택", font=get_font(13, True), fill=C_INK, anchor="mm")

    # Route Option 3
    draw.rounded_rectangle([40, 960, w - 40, 1055], radius=14, fill=C_CANVAS, outline=C_HAIRLINE, width=1)
    draw.rounded_rectangle([55, 975, 155, 1005], radius=15, fill=C_STEEL)
    draw.text((105, 990), "일반 경로 3", font=get_font(13, True), fill=C_ON_DARK, anchor="mm")
    draw.text((170, 977), "일반 도보 최단 경로", font=get_font(17, True), fill=C_INK)
    draw.text((55, 1015), "약 870m  |  단차 3곳 주의 (휠체어 비권장)", font=get_font(14, False), fill=C_ACCENT_ORANGE)
    draw.rounded_rectangle([w - 110, 985, w - 55, 1035], radius=25, fill=None, outline=C_HAIRLINE_STRONG, width=1)
    draw.text((w - 82, 1010), "선택", font=get_font(13, True), fill=C_INK, anchor="mm")

    # Start Navigation Button (button-on-dark: MongoDB Green Pill CTA)
    draw.rounded_rectangle([40, 1075, w - 40, 1145], radius=35, fill=C_BRAND_GREEN)
    draw.text((w // 2, 1110), "배리어프리 내비게이션 시작 ▶", font=get_font(18, True), fill=C_ON_PRIMARY, anchor="mm")

    img.save("assets/mockup_screen3.png")
    print("MongoDB-styled Screen 3 updated")

if __name__ == '__main__':
    create_screen1()
    create_screen2()
    create_screen3()
