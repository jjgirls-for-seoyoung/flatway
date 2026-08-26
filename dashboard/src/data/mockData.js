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
    image_url: "https://images.unsplash.com/photo-1613977257363-707ba9348227?auto=format&fit=crop&w=600&q=80",
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
    image_url: "https://images.unsplash.com/photo-1599740831144-53c2522af50e?auto=format&fit=crop&w=600&q=80",
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
    image_url: "https://images.unsplash.com/photo-1485965120184-e220f721d03e?auto=format&fit=crop&w=600&q=80",
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
    image_url: "https://images.unsplash.com/photo-1506157786151-b8491531f063?auto=format&fit=crop&w=600&q=80",
    is_verified: true,
    reported_at: new Date(Date.now() - 3600000 * 12).toISOString(),
    status: "processing"
  }
];

export const initialBuildings = [];

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
