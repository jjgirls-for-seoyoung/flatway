-- FlatWay Database Schema and Seed Data

-- 1. Create Hazards Table (단차, 노면 파손, 적치물 등)
CREATE TABLE IF NOT EXISTS hazards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type VARCHAR(50) NOT NULL, -- 'step' (단차), 'damage' (노면 파손), 'obstacle' (적치물), 'slope' (급경사)
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  step_height_cm NUMERIC,
  severity VARCHAR(20) NOT NULL, -- 'high' (통행 불가), 'medium' (불편), 'low' (경미)
  description TEXT,
  image_url TEXT,
  reported_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  is_verified BOOLEAN DEFAULT false NOT NULL,
  status VARCHAR(30) DEFAULT 'reported' NOT NULL
);

-- 2. Create Buildings Table (건물 접근성 및 편의 시설)
CREATE TABLE IF NOT EXISTS buildings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  has_ramp BOOLEAN DEFAULT false NOT NULL,
  ramp_slope_degree NUMERIC,
  has_elevator BOOLEAN DEFAULT false NOT NULL,
  main_entrance_type VARCHAR(50) DEFAULT 'manual' NOT NULL, -- 'automatic' (자동문), 'manual' (여닫이), 'revolving' (회전문)
  disabled_toilet BOOLEAN DEFAULT false NOT NULL,
  image_url TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Seed Initial Data (인천 작전역 및 작전여고 인근 샘플 데이터)
-- Clear existing data if needed
DELETE FROM hazards;
DELETE FROM buildings;

-- Seed Hazards
INSERT INTO hazards (type, latitude, longitude, step_height_cm, severity, description, is_verified, status)
VALUES 
  ('step', 37.5349, 126.7224, 4.5, 'high', '작전역 4번 출구 앞 보도 경계석 단차가 높아 휠체어 진입 불가', true, 'scheduled'),
  ('damage', 37.5365, 126.7235, NULL, 'medium', '작전여고 통학로 보도블록 파손 및 요철 심함', true, 'resolved'),
  ('obstacle', 37.5358, 126.7218, NULL, 'high', '횡단보도 앞 불법 주차 차량 및 자전거 적치물로 시야 확보 불가 및 통행 방해', false, 'reported'),
  ('slope', 37.5372, 126.7245, NULL, 'low', '주택가 이면도로 경사 다소 급함 (수동 휠체어 이용 시 주의 요함)', true, 'processing');

-- Seed Buildings
-- (건물 접근성 정보 삭제)

-- 4. Enable Realtime for tables (실시간 변경 사항 브로드캐스트 활성화)
-- 이 명령을 Supabase SQL Editor에서 실행해야 클라이언트로 실시간 변경 데이터가 수신됩니다.
begin;
  drop publication if exists supabase_realtime;
  create publication supabase_realtime for table hazards, buildings;
commit;

-- 5. Row Level Security (RLS) Policies (보안 및 데이터 관리 권한)
-- RLS 활성화 후 기본 CRUD 권한을 부여합니다.
ALTER TABLE public.hazards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public all on hazards" ON public.hazards;
CREATE POLICY "Allow public all on hazards" ON public.hazards FOR ALL TO public USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public all on buildings" ON public.buildings;
CREATE POLICY "Allow public all on buildings" ON public.buildings FOR ALL TO public USING (true) WITH CHECK (true);


-- 6. 제보 리워드 포인트 (계정별 포인트: 제보 1회당 1점)
-- 이 블록을 Supabase SQL Editor 에서 실행해야 적용된다. (앱 코드는 미적용 상태에서도 동작함)
-- 규칙: 이메일로 로그인한 계정이 '직접 제보'하면 포인트 +1.
--       익명(게스트) 제보와 센서 자동 감지(source = 'sensor')는 포인트가 쌓이지 않는다.

-- 6-1. hazards 에 제보자·출처 컬럼 추가
ALTER TABLE public.hazards ADD COLUMN IF NOT EXISTS reporter_id UUID;
ALTER TABLE public.hazards ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'manual' NOT NULL; -- 'manual' (직접 제보), 'sensor' (센서 자동)

-- 6-2. 계정별 포인트 테이블
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  points INTEGER DEFAULT 0 NOT NULL CHECK (points >= 0),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
-- 본인 포인트만 조회 가능. 클라이언트의 직접 INSERT/UPDATE/DELETE 정책은 만들지 않는다. (포인트는 아래 트리거로만 변경)
DROP POLICY IF EXISTS "Read own profile" ON public.profiles;
CREATE POLICY "Read own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- 6-3. 제보자 ID 는 클라이언트가 보낸 값을 믿지 않고 로그인 정보로 덮어쓴다.
CREATE OR REPLACE FUNCTION public.set_hazard_reporter() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.reporter_id := auth.uid();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_set_hazard_reporter ON public.hazards;
CREATE TRIGGER trg_set_hazard_reporter BEFORE INSERT ON public.hazards
  FOR EACH ROW EXECUTE FUNCTION public.set_hazard_reporter();

-- 6-4. 제보가 등록되면 제보자 계정의 포인트를 1 올린다.
CREATE OR REPLACE FUNCTION public.award_report_point() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.reporter_id IS NULL OR NEW.source = 'sensor' THEN
    RETURN NEW;
  END IF;
  -- 익명(게스트) 계정은 제외
  IF COALESCE((SELECT is_anonymous FROM auth.users WHERE id = NEW.reporter_id), true) THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.profiles (user_id, points) VALUES (NEW.reporter_id, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET points = public.profiles.points + 1, updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_award_report_point ON public.hazards;
CREATE TRIGGER trg_award_report_point AFTER INSERT ON public.hazards
  FOR EACH ROW EXECUTE FUNCTION public.award_report_point();
