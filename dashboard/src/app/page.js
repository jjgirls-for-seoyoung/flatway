"use client";

import { useEffect, useState } from 'react';
import { 
  MapPin, 
  AlertTriangle, 
  Building2, 
  Layers, 
  Navigation,
  Plus,
  HelpCircle,
  Database,
  Menu,
  X,
  Sun,
  Moon
} from 'lucide-react';
import DynamicMap from '../components/DynamicMap';
import ReportModal from '../components/ReportModal';
import { supabase } from '../lib/supabaseClient';
import { initialHazards, initialBuildings, mockRoutes } from '../data/mockData';

export default function Home() {
  const [hazards, setHazards] = useState([]);
  const [buildings, setBuildings] = useState([]);
  const [usingSupabase, setUsingSupabase] = useState(false);
  const [userLocation, setUserLocation] = useState(null);

  // Theme state ('dark' | 'light')
  const [theme, setTheme] = useState('dark');

  // Mobile drawer & detail card state
  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false);
  const [showMobileDetail, setShowMobileDetail] = useState(false);

  // Selector and filter states
  const [selectedRouteMode, setSelectedRouteMode] = useState('pedestrian');
  const [filters, setFilters] = useState({
    step: true,
    damage: true,
    building: true
  });

  // Selected item detail state
  const [selectedItem, setSelectedItem] = useState(null);
  const [selectedItemType, setSelectedItemType] = useState(null); // 'hazard' | 'building'

  // Report simulator modal states
  const [isReportModalOpen, setIsReportModalOpen] = useState(false);
  const [clickCoords, setClickCoords] = useState({ lat: 0, lng: 0 });

  // 1. Theme Initialization & Sync
  useEffect(() => {
    const savedTheme = localStorage.getItem('flatway_theme');
    if (savedTheme === 'light' || savedTheme === 'dark') {
      setTheme(savedTheme);
      document.documentElement.setAttribute('data-theme', savedTheme);
    } else {
      const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      const initialTheme = prefersDark ? 'dark' : 'light';
      setTheme(initialTheme);
      document.documentElement.setAttribute('data-theme', initialTheme);
    }
  }, []);

  const toggleTheme = () => {
    const nextTheme = theme === 'dark' ? 'light' : 'dark';
    setTheme(nextTheme);
    document.documentElement.setAttribute('data-theme', nextTheme);
    localStorage.setItem('flatway_theme', nextTheme);
  };

  // 1-1. Browser Geolocation Request
  useEffect(() => {
    if (typeof window !== 'undefined' && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const { latitude, longitude } = position.coords;
          setUserLocation([latitude, longitude]);
        },
        (error) => {
          console.warn("Browser geolocation denied or unavailable:", error);
        },
        { enableHighAccuracy: true, timeout: 10000 }
      );
    }
  }, []);

  // 2. Initial Data Fetching (Supabase with Local Storage fallback)
  useEffect(() => {
    async function loadData() {
      let supabaseHazards = null;
      let supabaseBuildings = null;

      if (supabase) {
        try {
          const { data: hData, error: hErr } = await supabase.from('hazards').select('*').order('reported_at', { ascending: false });
          const { data: bData, error: bErr } = await supabase.from('buildings').select('*');
          if (!hErr && !bErr) {
            supabaseHazards = hData;
            supabaseBuildings = bData;
          }
        } catch (err) {
          console.error("Failed to connect to Supabase database. Falling back.", err);
        }
      }

      if (supabaseHazards && supabaseBuildings) {
        setHazards(supabaseHazards);
        setBuildings(supabaseBuildings);
        setUsingSupabase(true);
      } else {
        // Fallback to localStorage
        const localHazards = localStorage.getItem('flatway_hazards');
        const localBuildings = localStorage.getItem('flatway_buildings');

        if (localHazards && localBuildings) {
          setHazards(JSON.parse(localHazards));
          setBuildings(JSON.parse(localBuildings));
        } else {
          // First-time seed
          localStorage.setItem('flatway_hazards', JSON.stringify(initialHazards));
          localStorage.setItem('flatway_buildings', JSON.stringify(initialBuildings));
          setHazards(initialHazards);
          setBuildings(initialBuildings);
        }
        setUsingSupabase(false);
      }
    }

    loadData();

    // Supabase Realtime Listener for Mobile App Live Reports and Buildings Updates
    if (supabase) {
      const channel = supabase
        .channel('realtime_flatway_channel')
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'hazards' },
          (payload) => {
            if (payload.eventType === 'INSERT') {
              setHazards(prev => {
                // Prevent duplicates if already added locally
                if (prev.some(h => h.id === payload.new.id)) return prev;
                return [payload.new, ...prev];
              });
            } else if (payload.eventType === 'UPDATE') {
              setHazards(prev => prev.map(h => h.id === payload.new.id ? payload.new : h));
            } else if (payload.eventType === 'DELETE') {
              setHazards(prev => prev.filter(h => h.id !== payload.old.id));
            }
          }
        )
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'buildings' },
          (payload) => {
            if (payload.eventType === 'INSERT') {
              setBuildings(prev => {
                // Prevent duplicates if already added locally
                if (prev.some(b => b.id === payload.new.id)) return prev;
                return [payload.new, ...prev];
              });
            } else if (payload.eventType === 'UPDATE') {
              setBuildings(prev => prev.map(b => b.id === payload.new.id ? payload.new : b));
            } else if (payload.eventType === 'DELETE') {
              setBuildings(prev => prev.filter(b => b.id !== payload.old.id));
            }
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(channel);
      };
    }
  }, []);

  // 3. Handle Map click (Trigger report modal)
  const handleMapClick = (lat, lng) => {
    setClickCoords({ lat, lng });
    setIsReportModalOpen(true);
  };

  // 4. Handle new report submission
  const handleReportSubmit = async (newReport) => {
    if (usingSupabase && supabase) {
      try {
        const { data, error } = await supabase.from('hazards').insert([newReport]).select();
        if (!error && data && data.length > 0) {
          const savedReport = data[0];
          setHazards(prev => [savedReport, ...prev]);
          setSelectedItem(savedReport);
          setSelectedItemType('hazard');
          setShowMobileDetail(true);
          alert('제보가 성공적으로 Supabase 서버에 반영되었습니다!');
          return;
        }
      } catch (err) {
        console.error("Supabase insert failed. Saving locally instead.", err);
      }
    }

    // Local Storage fallback
    const reportWithId = {
      ...newReport,
      id: `local_${Date.now()}`
    };
    const updatedHazards = [reportWithId, ...hazards];
    setHazards(updatedHazards);
    localStorage.setItem('flatway_hazards', JSON.stringify(updatedHazards));
    setSelectedItem(reportWithId);
    setSelectedItemType('hazard');
    setShowMobileDetail(true);
    alert('제보가 브라우저 로컬 저장소(localStorage)에 등록되었습니다!');
  };

  // 5. Handle item selection (Marker click)
  const handleSelectItem = (item, type) => {
    setSelectedItem(item);
    setSelectedItemType(type);
    setShowMobileDetail(true);
  };

  // 6. Toggle filters
  const toggleFilter = (key) => {
    setFilters(prev => ({
      ...prev,
      [key]: !prev[key]
    }));
  };

  // Calculations for stats & gauges
  const totalHazards = hazards.length;
  const activeStepsCount = hazards.filter(h => h.type === 'step').length;
  const totalBuildings = buildings.length;
  const buildingsWithRamp = buildings.filter(b => b.has_ramp).length;
  const rampPercentage = totalBuildings > 0 ? Math.round((buildingsWithRamp / totalBuildings) * 100) : 0;

  // Dynamic Safety Index Score
  const safetyScore = Math.max(
    0,
    Math.min(
      100,
      Math.round(
        100 - 
        hazards.filter(h => h.severity === 'high').length * 8 -
        hazards.filter(h => h.severity === 'medium').length * 4 -
        hazards.filter(h => h.severity === 'low').length * 1
      )
    )
  );

  // SVG Circle Stroke calculation (r = 32, circ = 201)
  const circumference = 201;
  const strokeDashoffset = circumference - (circumference * safetyScore) / 100;

  return (
    <main className="dashboard-container">
      {/* Mobile Backdrop Overlay */}
      <div 
        className={`sidebar-backdrop ${isMobileSidebarOpen ? 'open' : ''}`}
        onClick={() => setIsMobileSidebarOpen(false)}
      />

      {/* Sidebar (Desktop left panel & Mobile slide drawer) */}
      <aside className={`sidebar glass-panel ${isMobileSidebarOpen ? 'open' : ''}`}>
        {/* Header/Logo with Theme Toggle */}
        <div className="logo-section">
          <div className="logo-brand-group">
            <div className="logo-icon" style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <img 
                src="/logo.png" 
                alt="FlatWay Logo" 
                style={{ width: '100%', height: '100%', borderRadius: '10px', objectFit: 'cover' }}
              />
              <span 
                className={`db-status-dot ${usingSupabase ? 'online' : 'offline'}`} 
                title={usingSupabase ? 'Supabase 연동 완료' : '로컬 모크 데이터 모드'}
                style={{
                  position: 'absolute',
                  bottom: '-2px',
                  right: '-2px',
                  width: '10px',
                  height: '10px',
                  borderRadius: '50%',
                  backgroundColor: usingSupabase ? '#10b981' : '#ef4444',
                  border: '2px solid var(--bg-secondary)',
                  boxShadow: usingSupabase ? '0 0 6px #10b981' : '0 0 6px #ef4444',
                  zIndex: 10
                }}
              />
            </div>
            <div className="logo-text">
              <h1>FlatWay</h1>
              <p>휠체어·보행 약자 맞춤 경로 대시보드</p>
            </div>
          </div>
          <div className="logo-actions">
            <button 
              className="theme-toggle-btn" 
              onClick={toggleTheme}
              title={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
              aria-label={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
            >
              {theme === 'dark' ? <Sun size={17} /> : <Moon size={17} />}
            </button>
            {/* Mobile close button */}
            <button 
              className="mobile-sidebar-close" 
              onClick={() => setIsMobileSidebarOpen(false)}
              aria-label="메뉴 닫기"
            >
              <X size={20} />
            </button>
          </div>
        </div>



        {/* Safety Score Ring */}
        <div className="safety-score-container">
          <div className="score-circle">
            <svg>
              <circle className="bg-circle" cx="35" cy="35" r="32" />
              <circle 
                className="val-circle" 
                cx="35" 
                cy="35" 
                r="32" 
                style={{ strokeDashoffset }}
              />
            </svg>
            <div className="score-text-inner">{safetyScore}%</div>
          </div>
          <div className="score-info">
            <h3>보행 안전 종합 점수</h3>
            <p>현재 구역 내 위험 요인을 고려한 수치</p>
          </div>
        </div>

        {/* Stats Grid */}
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-header">
              <span style={{ fontSize: '11px' }}>총 노면 위험</span>
              <AlertTriangle size={14} color="var(--color-warn)" />
            </div>
            <div className="stat-value">{totalHazards}건</div>
            <div className="stat-label">단차 턱 포함</div>
          </div>
          <div className="stat-card">
            <div className="stat-header">
              <span style={{ fontSize: '11px' }}>건물 경사로율</span>
              <Building2 size={14} color="var(--color-safe)" />
            </div>
            <div className="stat-value">{rampPercentage}%</div>
            <div className="stat-label">진입 안전 보장</div>
          </div>
        </div>

        {/* Route Selector */}
        <div className="route-selector">
          <h4 className="section-title">
            <Navigation size={12} /> 이동 수단 및 안전 경로 모드
          </h4>
          <div className="route-options">
            <button 
              className={`route-btn ${selectedRouteMode === 'pedestrian' ? 'active' : ''}`}
              onClick={() => setSelectedRouteMode('pedestrian')}
            >
              <span>🚶</span>
              <span>보행자</span>
            </button>
            <button 
              className={`route-btn ${selectedRouteMode === 'electric' ? 'active' : ''}`}
              onClick={() => setSelectedRouteMode('electric')}
            >
              <span>⚡</span>
              <span>전동휠체어</span>
            </button>
            <button 
              className={`route-btn ${selectedRouteMode === 'manual' ? 'active' : ''}`}
              onClick={() => setSelectedRouteMode('manual')}
            >
              <span>♿</span>
              <span>수동휠체어</span>
            </button>
          </div>
          {mockRoutes[selectedRouteMode] && (
            <div style={{
              fontSize: '11px',
              color: 'var(--text-secondary)',
              background: 'var(--info-badge-bg)',
              padding: '8px 10px',
              borderRadius: '6px',
              marginTop: '4px',
              lineHeight: '1.4'
            }}>
              <strong>경로 설명: </strong>{mockRoutes[selectedRouteMode].notes}
            </div>
          )}
        </div>

        {/* Filter Panel */}
        <div className="control-panel">
          <h4 className="section-title">
            <Layers size={12} /> 지도 시각화 필터
          </h4>
          <div className="filter-group">
            <div className="filter-item" onClick={() => toggleFilter('step')}>
              <div className="filter-label-group">
                <span className="filter-dot step" />
                <span>단차 및 턱 노출 ({activeStepsCount}개)</span>
              </div>
              <label className="switch" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={filters.step} 
                  onChange={() => toggleFilter('step')} 
                />
                <span className="slider" />
              </label>
            </div>

            <div className="filter-item" onClick={() => toggleFilter('damage')}>
              <div className="filter-label-group">
                <span className="filter-dot damage" />
                <span>파손/급경사/적치물 노출 ({totalHazards - activeStepsCount}개)</span>
              </div>
              <label className="switch" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={filters.damage} 
                  onChange={() => toggleFilter('damage')} 
                />
                <span className="slider" />
              </label>
            </div>

            <div className="filter-item" onClick={() => toggleFilter('building')}>
              <div className="filter-label-group">
                <span className="filter-dot building" />
                <span>접근성 보장 건물 노출 ({totalBuildings}개)</span>
              </div>
              <label className="switch" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={filters.building} 
                  onChange={() => toggleFilter('building')} 
                />
                <span className="slider" />
              </label>
            </div>
          </div>
        </div>

        {/* Selected Item Detail panel */}
        <div className="detail-panel">
          <h4 className="section-title" style={{ borderBottom: '1px solid var(--glass-border)', paddingBottom: '6px', marginBottom: '4px' }}>
            🔍 세부 정보 조회
          </h4>
          {selectedItem ? (
            <div className="detail-body">
              {selectedItemType === 'hazard' ? (
                <>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span className="detail-header" style={{ color: 'var(--color-warn)' }}>
                      ⚠️ {selectedItem.type === 'step' ? '보행 단차 장애물' : 
                          selectedItem.type === 'damage' ? '보행 노면 파손' :
                          selectedItem.type === 'obstacle' ? '보행 적치물' : '보도 급경사'}
                    </span>
                    <span className={`detail-badge ${selectedItem.severity}`}>
                      위험도 {selectedItem.severity === 'high' ? '상' : selectedItem.severity === 'medium' ? '중' : '하'}
                    </span>
                  </div>
                  <p style={{ marginTop: '4px' }}>{selectedItem.description}</p>
                  {selectedItem.step_height_cm && (
                    <p style={{ fontSize: '12px', color: 'var(--text-primary)', marginTop: '4px' }}>
                      <strong>측정된 단차 높이:</strong> {selectedItem.step_height_cm} cm
                    </p>
                  )}
                  <p style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '6px' }}>
                    제보일시: {new Date(selectedItem.reported_at).toLocaleString('ko-KR')}
                  </p>
                </>
              ) : (
                <>
                  <span className="detail-header" style={{ color: 'var(--color-safe)' }}>
                    🏢 {selectedItem.name}
                  </span>
                  <p style={{ marginTop: '4px' }}>건물 입구 및 편의시설 배치 현황입니다.</p>
                  <ul style={{ listStyle: 'none', marginTop: '6px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
                    <li>
                      <strong>입구 경사로:</strong> {selectedItem.has_ramp ? `설치됨 (각도 ${selectedItem.ramp_slope_degree || '?'}°)` : '없음 (계단만 존재)'}
                    </li>
                    <li>
                      <strong>장애인 승강기:</strong> {selectedItem.has_elevator ? '설치 완료' : '미설치'}
                    </li>
                    <li>
                      <strong>출입문 개폐 방식:</strong> {selectedItem.main_entrance_type === 'automatic' ? '자동문' : selectedItem.main_entrance_type === 'revolving' ? '회전문' : '일반 여닫이 수동문'}
                    </li>
                    <li>
                      <strong>장애인 화장실:</strong> {selectedItem.disabled_toilet ? '있음' : '없음'}
                    </li>
                  </ul>
                </>
              )}
            </div>
          ) : (
            <div className="detail-panel-empty">
              지도 위에 배치된 핀(마커)을 탭하시면 해당 보행 장애물이나 건물의 접근성 상세 현황을 여기서 확인하실 수 있습니다.
            </div>
          )}
        </div>
      </aside>

      {/* Right / Main Map Section */}
      <section className="map-container" style={{ position: 'relative' }}>
        {/* Mobile Top Navigation & Route Quick Selector */}
        <div className="mobile-top-bar glass-panel">
          <div className="mobile-top-left">
            <button 
              className="mobile-menu-btn" 
              onClick={() => setIsMobileSidebarOpen(true)}
              aria-label="메뉴 열기"
            >
              <Menu size={20} />
            </button>
            <div className="mobile-brand" style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '8px' }}>
              <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <img 
                  src="/logo.png" 
                  alt="FlatWay Logo" 
                  style={{ width: '22px', height: '22px', borderRadius: '5px', objectFit: 'cover' }}
                />
                <span 
                  className={`db-status-dot ${usingSupabase ? 'online' : 'offline'}`} 
                  title={usingSupabase ? 'Supabase 연동 완료' : '로컬 모크 데이터 모드'}
                  style={{
                    position: 'absolute',
                    bottom: '-1px',
                    right: '-1px',
                    width: '7px',
                    height: '7px',
                    borderRadius: '50%',
                    backgroundColor: usingSupabase ? '#10b981' : '#ef4444',
                    border: '1.5px solid var(--bg-secondary)',
                    boxShadow: usingSupabase ? '0 0 4px #10b981' : '0 0 4px #ef4444',
                    zIndex: 10
                  }}
                />
              </div>
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                <span className="mobile-title">FlatWay</span>
                <span className="mobile-score-badge">안전 {safetyScore}%</span>
              </div>
            </div>
          </div>
          <div className="mobile-top-right">
            <div className="mobile-route-pills">
              <button 
                className={`mobile-route-pill ${selectedRouteMode === 'pedestrian' ? 'active' : ''}`}
                onClick={() => setSelectedRouteMode('pedestrian')}
                title="보행자 모드"
              >
                <span>🚶</span>
                <span>보행자</span>
              </button>
              <button 
                className={`mobile-route-pill ${selectedRouteMode === 'electric' ? 'active' : ''}`}
                onClick={() => setSelectedRouteMode('electric')}
                title="전동휠체어 모드"
              >
                <span>⚡</span>
                <span>전동</span>
              </button>
              <button 
                className={`mobile-route-pill ${selectedRouteMode === 'manual' ? 'active' : ''}`}
                onClick={() => setSelectedRouteMode('manual')}
                title="수동휠체어 모드"
              >
                <span>♿</span>
                <span>수동</span>
              </button>
            </div>
            <button 
              className="theme-toggle-btn" 
              onClick={toggleTheme}
              title={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
              aria-label={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
            >
              {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            </button>
          </div>
        </div>

        <DynamicMap 
          hazards={hazards}
          buildings={buildings}
          selectedRouteMode={selectedRouteMode}
          onMapClick={handleMapClick}
          onSelectItem={handleSelectItem}
          filters={filters}
          theme={theme}
          userLocation={userLocation}
        />

        {/* Mobile Floating Bottom Detail Card */}
        {selectedItem && showMobileDetail && (
          <div className="mobile-detail-card glass-panel">
            <div className="mobile-detail-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                {selectedItemType === 'hazard' ? (
                  <>
                    <span className="detail-header" style={{ color: 'var(--color-warn)', fontSize: '13px' }}>
                      ⚠️ {selectedItem.type === 'step' ? '보행 단차' : 
                          selectedItem.type === 'damage' ? '노면 파손' :
                          selectedItem.type === 'obstacle' ? '보행 적치물' : '보도 급경사'}
                    </span>
                    <span className={`detail-badge ${selectedItem.severity}`}>
                      위험도 {selectedItem.severity === 'high' ? '상' : selectedItem.severity === 'medium' ? '중' : '하'}
                    </span>
                  </>
                ) : (
                  <span className="detail-header" style={{ color: 'var(--color-safe)', fontSize: '13px' }}>
                    🏢 {selectedItem.name}
                  </span>
                )}
              </div>
              <button 
                className="mobile-card-close-btn"
                onClick={() => setShowMobileDetail(false)}
                aria-label="닫기"
              >
                <X size={16} />
              </button>
            </div>
            <div className="mobile-detail-content">
              {selectedItemType === 'hazard' ? (
                <>
                  <p style={{ fontSize: '12px', color: 'var(--text-primary)', marginTop: '2px' }}>{selectedItem.description}</p>
                  {selectedItem.step_height_cm && (
                    <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '2px' }}>
                      <strong>단차 높이:</strong> {selectedItem.step_height_cm} cm
                    </p>
                  )}
                  <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                    제보: {new Date(selectedItem.reported_at).toLocaleString('ko-KR')}
                  </p>
                </>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px 8px', fontSize: '11px', marginTop: '2px' }}>
                  <div><strong>경사로:</strong> {selectedItem.has_ramp ? `설치 (${selectedItem.ramp_slope_degree || '?'}°)` : '미설치'}</div>
                  <div><strong>승강기:</strong> {selectedItem.has_elevator ? '있음' : '없음'}</div>
                  <div><strong>출입문:</strong> {selectedItem.main_entrance_type === 'automatic' ? '자동문' : selectedItem.main_entrance_type === 'revolving' ? '회전문' : '여닫이문'}</div>
                  <div><strong>화장실:</strong> {selectedItem.disabled_toilet ? '장애인용' : '일반'}</div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Interactive instructions overlay */}
        <div className="map-overlay-instructions">
          <HelpCircle size={14} color="var(--color-accent)" />
          <span>지도의 빈 보행로를 클릭해 새로운 단차 제보 시뮬레이션을 실행해 보세요.</span>
        </div>
      </section>

      {/* Report Form Modal */}
      <ReportModal 
        isOpen={isReportModalOpen}
        onClose={() => setIsReportModalOpen(false)}
        onSubmit={handleReportSubmit}
        latitude={clickCoords.lat}
        longitude={clickCoords.lng}
      />
    </main>
  );
}
