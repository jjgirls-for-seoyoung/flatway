// FlatWay Mock Data Gyeyang Area (Incheon)

export const initialHazards = [
  {
    id: "Gyeyang_hazard_1",
    type: "step",
    latitude: 37.5349,
    longitude: 126.7224,
    step_height_cm: 4.5,
    severity: "high",
    description: "작전역 4번 출구 앞 보도 경계석 단차가 높아 휠체어 진입 불가",
    is_verified: true,
    reported_at: new Date(Date.now() - 3600000 * 24).toISOString(),
    status: "scheduled"
  },
  {
    id: "Gyeyang_hazard_2",
    type: "damage",
    latitude: 37.5365,
    longitude: 126.7235,
    step_height_cm: null,
    severity: "medium",
    description: "작전여고 통학로 보도블록 파손 및 요철 심함",
    is_verified: true,
    reported_at: new Date(Date.now() - 3600000 * 48).toISOString(),
    status: "resolved"
  },
  {
    id: "Gyeyang_hazard_3",
    type: "obstacle",
    latitude: 37.5358,
    longitude: 126.7218,
    step_height_cm: null,
    severity: "high",
    description: "횡단보도 앞 불법 주차 차량 및 자전거 적치물로 시야 확보 불가 및 통행 방해",
    is_verified: false,
    reported_at: new Date(Date.now() - 3600000 * 2).toISOString(),
    status: "reported"
  },
  {
    id: "Gyeyang_hazard_4",
    type: "slope",
    latitude: 37.5372,
    longitude: 126.7245,
    step_height_cm: null,
    severity: "low",
    description: "주택가 이면도로 경사 다소 급함 (수동 휠체어 이용 시 주의 요함)",
    is_verified: true,
    reported_at: new Date(Date.now() - 3600000 * 12).toISOString(),
    status: "processing"
  }
];

export const initialBuildings = [
  {
    id: "Gyeyang_bldg_1",
    name: "작전역 (인천1호선)",
    latitude: 37.5346,
    longitude: 126.7225,
    has_ramp: true,
    ramp_slope_degree: 4.5,
    has_elevator: true,
    main_entrance_type: "automatic",
    disabled_toilet: true,
    updated_at: new Date().toISOString()
  },
  {
    id: "Gyeyang_bldg_2",
    name: "작전여자고등학교",
    latitude: 37.5385,
    longitude: 126.7240,
    has_ramp: true,
    ramp_slope_degree: 8.0,
    has_elevator: true,
    main_entrance_type: "automatic",
    disabled_toilet: true,
    updated_at: new Date().toISOString()
  },
  {
    id: "Gyeyang_bldg_3",
    name: "작전1동 행정복지센터",
    latitude: 37.5360,
    longitude: 126.7250,
    has_ramp: true,
    ramp_slope_degree: 6.5,
    has_elevator: true,
    main_entrance_type: "automatic",
    disabled_toilet: true,
    updated_at: new Date().toISOString()
  },
  {
    id: "Gyeyang_bldg_4",
    name: "근처 상가빌딩",
    latitude: 37.5352,
    longitude: 126.7215,
    has_ramp: false,
    ramp_slope_degree: null,
    has_elevator: false,
    main_entrance_type: "manual",
    disabled_toilet: false,
    updated_at: new Date().toISOString()
  }
];

// Routes between Jakjeon Girls' HS [37.5385, 126.7240] and Jakjeon Station [37.5346, 126.7225]
export const mockRoutes = {
  // Direct but passes through road damage and high steps
  pedestrian: {
    name: "일반 보행로 경로 (최단거리)",
    color: "#94a3b8", // Gray
    distance: "510m",
    time: "8분",
    notes: "작전역 4번 출구 앞 높은 단차(4.5cm) 및 통학로 보도블록 파손 구간을 포함합니다.",
    coordinates: [
      [37.5385, 126.7240], // School
      [37.5365, 126.7235], // Road damage
      [37.5349, 126.7224], // High step
      [37.5346, 126.7225]  // Station
    ]
  },
  // Bypasses road damage and high step
  electric: {
    name: "전동 휠체어 추천 경로",
    color: "#3b82f6", // Blue
    distance: "620m",
    time: "5분",
    notes: "단차가 높고 노면이 파손된 통학로를 우회하여 평탄한 이면도로를 통해 이동합니다.",
    coordinates: [
      [37.5385, 126.7240],
      [37.5385, 126.7220],
      [37.5355, 126.7220],
      [37.5346, 126.7225]
    ]
  },
  // Bypasses road damage, high step and steep slopes
  manual: {
    name: "수동 휠체어 추천 경로 (최저 경사)",
    color: "#10b981", // Teal
    distance: "710m",
    time: "12분",
    notes: "단차와 파손 구간을 피할 뿐 아니라, 급경사 구간을 모두 피해 가장 부드러운 평지 위주로 우회합니다.",
    coordinates: [
      [37.5385, 126.7240],
      [37.5380, 126.7255],
      [37.5350, 126.7255],
      [37.5346, 126.7225]
    ]
  }
};
