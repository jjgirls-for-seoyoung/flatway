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

