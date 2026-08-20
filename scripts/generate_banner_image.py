import os
from PIL import Image, ImageDraw, ImageFont

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
C_BRAND_GREEN_MID = "#00A35C"
C_BRAND_GREEN_SOFT = "#C3F0D2"
C_BRAND_TEAL_DEEP = "#001E2B"
C_BRAND_TEAL = "#003D4F"
C_BRAND_TEAL_MID = "#00684A"
C_ON_PRIMARY = "#001E2B"
C_ACCENT_ORANGE = "#FA6E39"
C_ACCENT_PURPLE = "#7B3FF2"
C_ACCENT_BLUE = "#3D4F9F"
C_CANVAS = "#FFFFFF"
C_SURFACE = "#F9FBFA"
C_SURFACE_SOFT = "#F4F7F6"
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

def create_banner_image():
    W = 1800
    H = 5400
    SCALE = 3.0 # 3 pixels per mm

    def mm(val):
        return int(val * SCALE)

    img = Image.new("RGB", (W, H), C_SURFACE)
    draw = ImageDraw.Draw(img)

    # -------------------------------------------------------------
    # HEADER AREA (0 ~ 175mm = 0 ~ 525px) - MongoDB hero-band-dark
    # -------------------------------------------------------------
    draw.rectangle([0, 0, W, mm(175)], fill=C_BRAND_TEAL_DEEP)
    # Bottom Accent Line (Signature MongoDB Green)
    draw.rectangle([0, mm(170), W, mm(175)], fill=C_BRAND_GREEN)

    # Category Pill Badge (MongoDB badge-green style: rounded.full)
    draw.rounded_rectangle([mm(130), mm(18), mm(470), mm(44)], radius=mm(13), fill=C_BRAND_GREEN)
    f_badge = get_font(36, True)
    draw.text((W // 2, mm(31)), "AI · 디지털 기반 문제해결 · 창작 프로젝트", font=f_badge, fill=C_ON_PRIMARY, anchor="mm")

    # Main Title
    f_title = get_font(108, True)
    draw.text((W // 2, mm(80)), "플랫웨이 (FlatWay)", font=f_title, fill=C_ON_DARK, anchor="mm")

    # Subtitle
    f_sub = get_font(44, True)
    draw.text((W // 2, mm(118)), "휠체어와 이동 약자를 위한 실시간 단차 및 노면 파손 안내 지도", font=f_sub, fill=C_BRAND_GREEN_SOFT, anchor="mm")

    # Slogan Banner (MongoDB dark card with green border)
    draw.rounded_rectangle([mm(50), mm(134), mm(550), mm(164)], radius=mm(15), fill=C_BRAND_TEAL, outline=C_BRAND_GREEN, width=3)
    f_slogan = get_font(36, True)
    draw.text((W // 2, mm(149)), "“턱 없는 세상, 안심하고 달리는 평평한 길을 연결합니다”", font=f_slogan, fill=C_ON_DARK, anchor="mm")

    # Helper function for Section Headers (MongoDB style: dark teal pill with green indicator)
    def draw_section_header(title_num, title_text, y_mm):
        y_px = mm(y_mm)
        h_px = mm(26)
        draw.rounded_rectangle([mm(25), y_px, mm(575), y_px + h_px], radius=mm(13), fill=C_BRAND_TEAL_DEEP)
        draw.rounded_rectangle([mm(25), y_px, mm(33), y_px + h_px], radius=mm(4), fill=C_BRAND_GREEN)
        f_sec = get_font(40, True)
        draw.text((mm(45), y_px + h_px // 2), f"{title_num}. {title_text}", font=f_sec, fill=C_ON_DARK, anchor="lm")

    # -------------------------------------------------------------
    # 1. 기본 정보 (188 ~ 265mm) - MongoDB card-base
    # -------------------------------------------------------------
    draw_section_header("1", "기본 정보", 188)
    draw.rounded_rectangle([mm(25), mm(218), mm(575), mm(265)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    # 3 Category Pills
    pill_data = [
        (mm(35), mm(195), "[학교명]", "작전여자고등학교", C_SURFACE, C_HAIRLINE_STRONG, C_STEEL, C_INK),
        (mm(217), mm(377), "[팀명]", "사대천왕", C_SURFACE_FEATURE, C_BRAND_GREEN, C_BRAND_GREEN_DARK, C_BRAND_GREEN_DARK),
        (mm(400), mm(565), "[프로젝트명]", "플랫웨이 (FlatWay)", "#FAF5FF", "#E9D5FF", C_ACCENT_PURPLE, C_ACCENT_PURPLE)
    ]
    for x1, x2, label, val, bg_c, bord_c, lbl_c, val_c in pill_data:
        draw.rounded_rectangle([x1, mm(224), x2, mm(259)], radius=mm(17), fill=bg_c, outline=bord_c, width=2)
        draw.text(((x1 + x2) // 2, mm(234)), label, font=get_font(28, True), fill=lbl_c, anchor="mm")
        draw.text(((x1 + x2) // 2, mm(248)), val, font=get_font(34, True), fill=val_c, anchor="mm")

    # -------------------------------------------------------------
    # 2. 문제 정의 (275 ~ 445mm) - MongoDB card-base with category accents
    # -------------------------------------------------------------
    draw_section_header("2", "문제 정의 (배경 및 필요성)", 275)
    draw.rounded_rectangle([mm(25), mm(305), mm(575), mm(445)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    f_subh = get_font(34, True)
    f_body = get_font(28, False)

    # Problem Tag (MongoDB Accent Orange Badge)
    draw.rounded_rectangle([mm(40), mm(316), mm(220), mm(332)], radius=mm(8), fill="#FFF8E0", outline=C_ACCENT_ORANGE, width=1)
    draw.text((mm(130), mm(324)), "[어떤 문제를 발견했는가?]", font=get_font(24, True), fill=C_ACCENT_ORANGE, anchor="mm")

    draw.text((mm(40), mm(338)), "• 휠체어·유모차 이용자는 보행로의 높은 단차(턱)나 파손된 노면을 미리 알 수 없어, 이미 진입한 길에서 되돌아오거나", font=f_body, fill=C_INK)
    draw.text((mm(56), mm(350)), "위험한 차도로 우회해야 하는 심각한 이동권 침해와 안전사고 위험을 겪고 있음.", font=f_body, fill=C_INK)

    # Why Tag (MongoDB Brand Green Soft Badge)
    draw.rounded_rectangle([mm(40), mm(366), mm(290), mm(382)], radius=mm(8), fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN_DARK, width=1)
    draw.text((mm(165), mm(374)), "[왜 해결이 필요한가? (기존 한계)]", font=get_font(24, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.text((mm(40), mm(388)), "• 기존 상용 지도 앱은 차량 위주이거나 단순 최단 도보 경로만 제공하여 휠체어 통행에 필수적인 노면 파손·단차·", font=f_body, fill=C_INK)
    draw.text((mm(56), mm(400)), "경사도 등 세부 보행 장애 정보를 전혀 제공하지 못함.", font=f_body, fill=C_INK)

    # Persona Quote Box (MongoDB why-card with subtle accent)
    draw.rounded_rectangle([mm(38), mm(412), mm(562), mm(440)], radius=mm(8), fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN_SOFT, width=2)
    draw.text((mm(48), mm(420)), "● 사용자 페르소나 (김민준, 24세 전동휠체어 대학생)", font=get_font(26, True), fill=C_BRAND_GREEN_DARK)
    draw.text((mm(48), mm(431)), "“등하굣길에 예상치 못한 턱에 막혀 차도로 돌아가야 했던 위험한 순간이 많았습니다. 미리 알고 피할 수 있다면 안심하고 다닐 수 있어요.”", font=get_font(25, False), fill=C_INK)

    # -------------------------------------------------------------
    # 3. 해결 아이디어 (455 ~ 630mm) - MongoDB 3-tier / category cards
    # -------------------------------------------------------------
    draw_section_header("3", "해결 아이디어 (핵심 솔루션)", 455)
    draw.rounded_rectangle([mm(25), mm(485), mm(575), mm(630)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    sol_items = [
        ("① 맞춤 이동 수단별 안전 경로", "보행자 / 수동휠체어 / 전동휠체어 특성을 반영하여 '단차 최소 경로' 및 '파손 최소 경로'를 구분하여 최적의 안전 우회로 추천", C_SURFACE_FEATURE, C_BRAND_GREEN, C_BRAND_GREEN_DARK),
        ("② 실시간 참여형 위험 제보", "보행 중 발견한 턱이나 파손 도로를 사용자가 사진과 함께 원클릭으로 등록하고 지도에 실시간 공유", "#FAF5FF", "#E9D5FF", C_ACCENT_PURPLE),
        ("③ 건물 접근성 정보 연계", "도착지 건물의 주출입구 경사로 유무 및 엘리베이터 위치 정보를 상세히 제공하여 헛걸음 방지", "#EFF6FF", "#BFDBFE", C_ACCENT_BLUE)
    ]

    for idx, (s_title, s_desc, bg_c, bord_c, acc_c) in enumerate(sol_items):
        y1 = mm(495 + idx * 43)
        y2 = y1 + mm(38)
        draw.rounded_rectangle([mm(38), y1, mm(562), y2], radius=mm(8), fill=bg_c, outline=bord_c, width=2)
        draw.text((mm(50), y1 + mm(6)), s_title, font=get_font(32, True), fill=acc_c)
        draw.text((mm(50), y1 + mm(20)), s_desc, font=get_font(27, False), fill=C_INK)

    # -------------------------------------------------------------
    # 4. AI·디지털 활용 과정 (640 ~ 810mm) - MongoDB SIGNATURE DARK TERMINAL CARD
    # -------------------------------------------------------------
    draw_section_header("4", "AI · 디지털 도구 활용 과정", 640)
    # Dark Canvas Container (MongoDB code-mockup-card / card-feature-dark)
    draw.rounded_rectangle([mm(25), mm(670), mm(575), mm(810)], radius=mm(12), fill=C_BRAND_TEAL_DEEP, outline=C_BRAND_TEAL, width=2)

    # Terminal Top Window Controls (Red, Yellow, Green dots)
    draw.ellipse([mm(35), mm(677), mm(39), mm(681)], fill="#EF4444")
    draw.ellipse([mm(42), mm(677), mm(46), mm(681)], fill="#F59E0B")
    draw.ellipse([mm(49), mm(677), mm(53), mm(681)], fill=C_BRAND_GREEN)
    draw.text((mm(60), mm(679)), "FlatWay Core Tech Stack & Architecture", font=get_font(20, True), fill=C_ON_DARK_MUTED, anchor="lm")

    tech_items = [
        ("스마트폰 센서 (IoT & Sensor Data)", "GPS & 가속도 센서 연동 알고리즘", "휠체어 이동 중 발생하는 진동·충격 가속도 데이터를 실시간 수집하여 노면 파손과 단차 위치를 자동 감지", C_BRAND_GREEN),
        ("지도 API 및 공간정보 (Spatial Platform)", "Kakao Maps & VWorld API 연동", "실제 보행 네트워크에 경사도와 노면 상태 레이어를 결합하여 휠체어 전용 가중치 기반 최적 경로 알고리즘 구축", "#38BDF8"),
        ("UI/UX 디자인 도구 (Design System)", "Figma & Euclid 컴포넌트 설계", "이동 약자의 사용 편의성과 직관성을 고려하여 '검색 → 수단 선택 → 맞춤 안내' 3단계 인터페이스 설계", C_BRAND_GREEN_SOFT)
    ]

    for idx, (t_title, t_sub, t_desc, code_c) in enumerate(tech_items):
        y1 = mm(688 + idx * 39)
        y2 = y1 + mm(35)
        draw.rounded_rectangle([mm(35), y1, mm(565), y2], radius=mm(6), fill=C_BRAND_TEAL, outline=C_HAIRLINE_DARK, width=1)
        draw.text((mm(45), y1 + mm(5)), f"▶ {t_title}   |   {t_sub}", font=get_font(28, True), fill=code_c)
        draw.text((mm(45), y1 + mm(18)), t_desc, font=get_font(25, False), fill=C_ON_DARK)

    # -------------------------------------------------------------
    # 5. 테스트 및 개선 과정 (820 ~ 985mm) - MongoDB card-base
    # -------------------------------------------------------------
    draw_section_header("5", "테스트 및 개선 과정", 820)
    draw.rounded_rectangle([mm(25), mm(850), mm(575), mm(985)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    # Sub 1 (Mint Featured)
    draw.rounded_rectangle([mm(38), mm(858), mm(562), mm(914)], radius=mm(8), fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=2)
    draw.text((mm(50), mm(865)), "● [현장 실증 답사] 작전여고 ~ 작전역 구간 보행로 현장 조사 및 데이터 검증", font=get_font(30, True), fill=C_BRAND_GREEN_DARK)
    draw.text((mm(50), mm(879)), "• 학교 주변 실제 통행로를 직접 답사하며 보도턱 높이(3~7cm) 및 노면 파손 지점을 실측 조사함.", font=get_font(26, False), fill=C_INK)
    draw.text((mm(50), mm(892)), "• 수집된 실측 데이터와 지도 API 경로를 비교 분석하여 휠체어 통행 불가 지점을 정확히 식별함.", font=get_font(26, False), fill=C_INK)

    # Sub 2 (Blue Category)
    draw.rounded_rectangle([mm(38), mm(920), mm(562), mm(976)], radius=mm(8), fill="#EFF6FF", outline="#BFDBFE", width=2)
    draw.text((mm(50), mm(927)), "● [개선 내용] 사용자 제보 신뢰도 검증 및 도로 상태 최신화 프로세스 설계", font=get_font(30, True), fill=C_ACCENT_BLUE)
    draw.text((mm(50), mm(941)), "• 초기 아이디어의 허위/오래된 제보 문제를 해결하기 위해 '운영자 1차 필터링 + 다수 사용자 교차 확인' 시스템을", font=get_font(26, False), fill=C_INK)
    draw.text((mm(50), mm(954)), "추가 설계하여 데이터의 신뢰성과 실시간성을 대폭 개선함.", font=get_font(26, False), fill=C_INK)

    # -------------------------------------------------------------
    # 6. 결과물 주요 화면 (995 ~ 1445mm) - MongoDB App Mockups
    # -------------------------------------------------------------
    draw_section_header("6", "결과물 주요 화면 및 핵심 기능", 995)
    draw.rounded_rectangle([mm(25), mm(1025), mm(575), mm(1445)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    mockup_info = [
        ("assets/mockup_screen1.png", mm(38), "화면 ① [출발·도착지 & 단차 제보]", "• 현재 위치 기반 목적지 검색\n• 현장 사진 첨부 실시간 제보 UI"),
        ("assets/mockup_screen2.png", mm(218), "화면 ② [이동 수단 맞춤 선택]", "• 보행자 / 수동·전동 휠체어 선택\n• 수단별 예상시간 & 안전도 비교"),
        ("assets/mockup_screen3.png", mm(397), "화면 ③ [맞춤 안전경로 안내]", "• 파손 최소 안심길 & 단차 우회 안내\n• 경사로/엘리베이터 출입구 표시")
    ]

    for m_path, x_px, m_title, m_desc in mockup_info:
        if os.path.exists(m_path):
            m_img = Image.open(m_path).convert("RGBA")
            m_resized = m_img.resize((mm(165), mm(330)), Image.Resampling.LANCZOS)
            img.paste(m_resized, (x_px, mm(1038)), m_resized)

        # Caption Box (MongoDB style)
        cap_y1 = mm(1374)
        cap_y2 = mm(1434)
        draw.rounded_rectangle([x_px, cap_y1, x_px + mm(165), cap_y2], radius=mm(8), fill=C_SURFACE, outline=C_HAIRLINE, width=2)
        draw.text((x_px + mm(165) // 2, cap_y1 + mm(6)), m_title, font=get_font(28, True), fill=C_BRAND_TEAL_DEEP, anchor="mt")
        
        lines = m_desc.split('\n')
        for l_idx, line in enumerate(lines):
            draw.text((x_px + mm(8), cap_y1 + mm(22 + l_idx * 16)), line, font=get_font(24, False), fill=C_INK)

    # -------------------------------------------------------------
    # 7. 기대효과 (1455 ~ 1615mm) - MongoDB Impact cards
    # -------------------------------------------------------------
    draw_section_header("7", "기대효과 및 활용 가능성", 1455)
    draw.rounded_rectangle([mm(25), mm(1485), mm(575), mm(1615)], radius=mm(12), fill=C_CANVAS, outline=C_HAIRLINE, width=2)

    # Col 1 (Mint Feature)
    draw.rounded_rectangle([mm(38), mm(1495), mm(295), mm(1603)], radius=mm(8), fill=C_SURFACE_FEATURE, outline=C_BRAND_GREEN, width=2)
    draw.text((mm(50), mm(1503)), "● 이동 약자의 안전한 통행권 보장", font=get_font(30, True), fill=C_BRAND_GREEN_DARK)
    draw.text((mm(50), mm(1522)), "• 도로 턱과 파손 구역을 사전에 회피하여 통행 막힘 및 위험", font=get_font(25, False), fill=C_INK)
    draw.text((mm(50), mm(1536)), "차도 우회 사고를 원천 방지함.", font=get_font(25, False), fill=C_INK)
    draw.text((mm(50), mm(1554)), "• 불필요한 우회 이동 시간을 단축하고 외출 시의 심리적", font=get_font(25, False), fill=C_INK)
    draw.text((mm(50), mm(1568)), "불안감을 크게 해소함.", font=get_font(25, False), fill=C_INK)

    # Col 2 (Purple Category)
    draw.rounded_rectangle([mm(305), mm(1495), mm(562), mm(1603)], radius=mm(8), fill="#FAF5FF", outline="#E9D5FF", width=2)
    draw.text((mm(317), mm(1503)), "● 배리어프리 도시 인프라 연계", font=get_font(30, True), fill=C_ACCENT_PURPLE)
    draw.text((mm(317), mm(1522)), "• 시민 참여형 노면 데이터를 축적하여 지자체 도로 보수 행정", font=get_font(25, False), fill=C_INK)
    draw.text((mm(317), mm(1536)), "및 우선 정비 구역 선정에 직접 활용 가능.", font=get_font(25, False), fill=C_INK)
    draw.text((mm(317), mm(1554)), "• 유모차, 고령자 등 모든 보행 약자로 수혜를 확장하여", font=get_font(25, False), fill=C_INK)
    draw.text((mm(317), mm(1568)), "모두를 위한 포용적 도시 환경 조성.", font=get_font(25, False), fill=C_INK)

    # -------------------------------------------------------------
    # 8. QR코드 삽입 영역 (1625 ~ 1775mm)
    # -------------------------------------------------------------
    draw.rounded_rectangle([mm(25), mm(1625), mm(575), mm(1775)], radius=mm(12), fill=C_SURFACE, outline=C_HAIRLINE_STRONG, width=2)
    
    # QR box
    qr_x = W // 2 - mm(45)
    draw.rounded_rectangle([qr_x, mm(1636), qr_x + mm(90), mm(1726)], radius=mm(8), fill=C_CANVAS, outline=C_BRAND_GREEN, width=2)
    draw.text((W // 2, mm(1668)), "QR CODE", font=get_font(32, True), fill=C_BRAND_TEAL_DEEP, anchor="mm")
    draw.text((W // 2, mm(1694)), "삽입 영역", font=get_font(28, True), fill=C_BRAND_GREEN_DARK, anchor="mm")

    draw.text((W // 2, mm(1748)), "※ QR코드는 운영사에서 추후 일괄 적용 예정", font=get_font(32, True), fill=C_STEEL, anchor="mm")

    # Save High-Res PNG
    out_png = "flatway_xbanner_preview.png"
    img.save(out_png, "PNG")
    print(f"MongoDB High-res PNG saved to {out_png}")

    # Save PDF (150 DPI)
    out_pdf = "flatway_xbanner_600x1800.pdf"
    img.save(out_pdf, "PDF", resolution=150.0)
    print(f"MongoDB PDF saved to {out_pdf}")

    # Save thumbnail for artifact
    thumb = img.resize((600, 1800), Image.Resampling.LANCZOS)
    thumb.save("assets/banner_thumbnail.png", "PNG")
    print("Thumbnail saved to assets/banner_thumbnail.png")

if __name__ == '__main__':
    create_banner_image()
