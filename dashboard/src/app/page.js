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
  Moon,
  Search,
  Trash2,
  Wrench,
  Info,
  AlertCircle,
  Eye,
  BookOpen,
  ChevronDown,
  ChevronUp,
  User
} from 'lucide-react';
import DynamicMap from '../components/DynamicMap';
import ReportModal from '../components/ReportModal';
import AuthModal from '../components/AuthModal';
import { supabase } from '../lib/supabaseClient';
import { initialHazards, initialBuildings, mockRoutes } from '../data/mockData';

export default function Home() {
  const [hazards, setHazards] = useState([]);
  const [buildings, setBuildings] = useState([]);
  const [usingSupabase, setUsingSupabase] = useState(false);
  const [userLocation, setUserLocation] = useState(null);

  // Search states
  const [searchQuery, setSearchQuery] = useState('');
  const [searchLocation, setSearchLocation] = useState(null);
  const [isSearching, setIsSearching] = useState(false);
  const [searchError, setSearchError] = useState('');

  // Control center heatmap mode state
  const [heatmapMode, setHeatmapMode] = useState(false);

  // Right sidebar help and guide states
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(false);
  const [expandedSection, setExpandedSection] = useState(0);

  const toggleAccordion = (idx) => {
    setExpandedSection(expandedSection === idx ? null : idx);
  };

  // Theme state ('dark' | 'light')
  const [theme, setTheme] = useState('dark');

  // Auth states
  const [user, setUser] = useState(null);
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);

  // Mobile drawer & detail card state
  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false);
  const [showMobileDetail, setShowMobileDetail] = useState(false);

  // Selector and filter states
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

  // 1-2. Supabase Auth Session Listener
  useEffect(() => {
    if (supabase) {
      supabase.auth.getSession().then(({ data: { session } }) => {
        setUser(session?.user ?? null);
      });

      const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
        setUser(session?.user ?? null);
      });

      return () => subscription.unsubscribe();
    }
  }, []);

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
              setSelectedItem(prev => (prev && prev.id === payload.new.id) ? { ...prev, ...payload.new } : prev);
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
    const reportToSave = {
      ...newReport,
      status: 'reported',
      reported_at: new Date().toISOString()
    };

    if (usingSupabase && supabase) {
      try {
        const { data, error } = await supabase.from('hazards').insert([reportToSave]).select();
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
      ...reportToSave,
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

  // 5-2. Handle Maintenance Status Change
  const handleStatusChange = async (id, newStatus) => {
    // Update locally first
    setHazards(prev => prev.map(h => h.id === id ? { ...h, status: newStatus } : h));
    setSelectedItem(prev => (prev && prev.id === id) ? { ...prev, status: newStatus } : prev);

    // Update in Supabase if connected
    if (usingSupabase && supabase) {
      try {
        const { error } = await supabase
          .from('hazards')
          .update({ status: newStatus })
          .eq('id', id);
        
        if (error) {
          console.error("Failed to update status in Supabase:", error.message || error);
        }
      } catch (err) {
        console.error("Supabase status update error:", err);
      }
    }
  };

  // 5-3. Handle Item Deletion (Hazards or Buildings)
  const handleDeleteItem = async (id, type) => {
    if (!confirm('정말로 이 정보를 데이터베이스에서 삭제하시겠습니까?')) return;

    // Update locally first
    if (type === 'hazard') {
      setHazards(prev => prev.filter(h => h.id !== id));
      if (!usingSupabase) {
        const stored = localStorage.getItem('flatway_hazards');
        if (stored) {
          const parsed = JSON.parse(stored);
          localStorage.setItem('flatway_hazards', JSON.stringify(parsed.filter(h => h.id !== id)));
        }
      }
    } else if (type === 'building') {
      setBuildings(prev => prev.filter(b => b.id !== id));
    }

    // Clear selected item
    setSelectedItem(null);
    setSelectedItemType(null);

    // Delete in Supabase if connected
    if (usingSupabase && supabase) {
      try {
        const { error } = await supabase
          .from(type === 'hazard' ? 'hazards' : 'buildings')
          .delete()
          .eq('id', id);

        if (error) {
          console.error(`Failed to delete ${type} from Supabase:`, error.message || error);
          alert(`서버에서 삭제에 실패했습니다: ${error.message}`);
        } else {
          alert('데이터베이스에서 성공적으로 삭제되었습니다!');
        }
      } catch (err) {
        console.error("Supabase delete error:", err);
      }
    } else {
      alert('로컬 상태에서 성공적으로 삭제되었습니다!');
    }
  };

  // 5. Handle item selection (Marker click)
  const handleSelectItem = (item, type) => {
    setSelectedItem(item);
    setSelectedItemType(type);
    setShowMobileDetail(true);
  };

  // 5-1. Handle Location Search (Nominatim Geocoding API)
  const handleSearchSubmit = async (e) => {
    e.preventDefault();
    if (!searchQuery.trim()) return;

    setIsSearching(true);
    setSearchError('');

    try {
      const response = await fetch(
        `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(searchQuery)}`
      );
      const data = await response.json();

      if (data && data.length > 0) {
        const firstResult = data[0];
        const lat = parseFloat(firstResult.lat);
        const lon = parseFloat(firstResult.lon);
        setSearchLocation([lat, lon]);
      } else {
        setSearchError('검색 결과를 찾을 수 없습니다.');
      }
    } catch (err) {
      console.error("Geocoding failed:", err);
      setSearchError('검색 중 오류가 발생했습니다.');
    } finally {
      setIsSearching(false);
    }
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

  // Maintenance pipeline stats
  const countByStatus = (statusName) => hazards.filter(h => (h.status || 'reported') === statusName).length;
  const reportedCount = countByStatus('reported');
  const processingCount = countByStatus('processing');
  const scheduledCount = countByStatus('scheduled');
  const resolvedCount = countByStatus('resolved');

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
                style={{ width: '100%', height: '100%', borderRadius: 'var(--ldsg-radius-200)', objectFit: 'cover' }}
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
              <p>대시보드</p>
            </div>
          </div>
          <div className="logo-actions" style={{ display: 'flex', gap: '6px' }}>
            <button 
              className="theme-toggle-btn" 
              onClick={() => setIsRightSidebarOpen(prev => !prev)}
              title="도움말 및 기준서 보기"
              aria-label="도움말 및 기준서 보기"
            >
              <BookOpen size={16} />
            </button>
            <button 
              className="theme-toggle-btn" 
              onClick={toggleTheme}
              title={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
              aria-label={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
            >
              {theme === 'dark' ? <Sun size={17} /> : <Moon size={17} />}
            </button>
            <button 
              className="theme-toggle-btn" 
              onClick={() => setIsAuthModalOpen(true)}
              title={user ? `${user.email} (로그아웃)` : '로그인 / 회원가입'}
              aria-label="로그인 / 회원가입"
            >
              <User size={16} />
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



        {/* Location Search Container */}
        <div className="search-container glass-panel" style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '8px',
          padding: '14px 16px',
          borderRadius: 'var(--ldsg-radius-300)',
          background: 'var(--card-bg)',
          border: '1px solid var(--glass-border)',
          marginBottom: '8px'
        }}>
          <h3 style={{ fontSize: '13px', fontWeight: '700', color: 'var(--text-primary)', margin: 0, display: 'flex', alignItems: 'center', gap: '6px' }}>
            <Search size={14} color="var(--color-accent)" /> 위치 및 목적지 검색
          </h3>
          <form onSubmit={handleSearchSubmit} style={{ display: 'flex', gap: '6px', width: '100%' }}>
            <input
              type="text"
              placeholder="예: 서울시청, 작전역"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{
                flex: 1,
                padding: '8px 12px',
                borderRadius: 'var(--ldsg-radius-200)',
                border: '1px solid var(--glass-border)',
                background: 'var(--bg-secondary)',
                color: 'var(--text-primary)',
                fontSize: '12px',
                outline: 'none',
                width: '60%'
              }}
            />
            <button
              type="submit"
              disabled={isSearching}
              style={{
                padding: '8px 14px',
                borderRadius: 'var(--ldsg-radius-200)',
                border: 'none',
                background: 'var(--color-accent)',
                color: 'white',
                fontSize: '12px',
                fontWeight: '600',
                cursor: 'pointer',
                transition: 'background 0.2s',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0
              }}
            >
              {isSearching ? '검색중' : '검색'}
            </button>
          </form>
          {searchError && (
            <p style={{ margin: 0, fontSize: '11px', color: '#ef4444', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <AlertCircle size={12} color="#ef4444" /> {searchError}
            </p>
          )}
        </div>

        {/* Heatmap & Maintenance Control Center */}
        <div className="control-panel glass-panel" style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '8px',
          padding: '12px 14px',
          borderRadius: 'var(--ldsg-radius-300)',
          background: 'var(--card-bg)',
          border: '1px solid var(--glass-border)',
          marginBottom: '8px'
        }}>
          <h4 className="section-title" style={{ margin: 0, fontSize: '12px', fontWeight: '700', color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Eye size={12} color="var(--color-accent)" /> 실시간 관제 및 분석 모드
          </h4>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 0' }}>
            <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>열지도(Heatmap) 분석 활성화</span>
            <label className="switch" style={{ margin: 0 }}>
              <input 
                type="checkbox" 
                checked={heatmapMode} 
                onChange={() => setHeatmapMode(prev => !prev)} 
              />
              <span className="slider" />
            </label>
          </div>
        </div>

        {/* Municipal Maintenance Dashboard */}
        <div className="maintenance-board glass-panel" style={{
          padding: '12px 14px',
          borderRadius: 'var(--ldsg-radius-300)',
          background: 'var(--info-badge-bg)',
          border: '1px solid var(--info-badge-border)',
          marginBottom: '10px'
        }}>
          <h4 style={{ fontSize: '12px', fontWeight: '700', color: 'var(--text-primary)', margin: '0 0 8px 0', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <Wrench size={12} color="var(--color-accent)" /> 보도 유지보수 파이프라인 현황
          </h4>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '6px', textAlign: 'center' }}>
            <div style={{ background: 'rgba(59, 130, 246, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(59, 130, 246, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>접수</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#3b82f6' }}>{reportedCount}</div>
            </div>
            <div style={{ background: 'rgba(139, 92, 246, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(139, 92, 246, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>조사중</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#8b5cf6' }}>{processingCount}</div>
            </div>
            <div style={{ background: 'rgba(249, 115, 22, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(249, 115, 22, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>보수예정</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#f97316' }}>{scheduledCount}</div>
            </div>
            <div style={{ background: 'rgba(16, 185, 129, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(16, 185, 129, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>완료</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#10b981' }}>{resolvedCount}</div>
            </div>
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
          <h4 className="section-title" style={{ borderBottom: '1px solid var(--glass-border)', paddingBottom: '6px', marginBottom: '4px', display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Info size={12} color="var(--color-accent)" /> 세부 정보 조회
          </h4>
          {selectedItem ? (
            <div className="detail-body">
              {selectedItemType === 'hazard' ? (
                <>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span className="detail-header" style={{ color: 'var(--color-warn)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <AlertTriangle size={14} />
                      {selectedItem.type === 'step' ? '보행 단차 장애물' : 
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
                  {/* Status badge & change dropdown */}
                  <div style={{ marginTop: '12px', padding: '10px 12px', borderRadius: 'var(--ldsg-radius-300)', background: 'var(--bg-secondary)', border: '1px solid var(--glass-border)' }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11px', fontWeight: '700', color: 'var(--text-secondary)', marginBottom: '6px' }}>
                      <Wrench size={12} /> 유지보수 진행 관리
                    </label>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span className={`status-badge ${selectedItem.status || 'reported'}`}>
                        {(selectedItem.status || 'reported') === 'reported' ? '접수됨' :
                         selectedItem.status === 'processing' ? '조사중' :
                         selectedItem.status === 'scheduled' ? '보수 예정' : '보수 완료'}
                      </span>
                      <select
                        className="status-select"
                        value={selectedItem.status || 'reported'}
                        onChange={(e) => handleStatusChange(selectedItem.id, e.target.value)}
                      >
                        <option value="reported">접수 (Reported)</option>
                        <option value="processing">조사중 (Processing)</option>
                        <option value="scheduled">보수 예정 (Scheduled)</option>
                        <option value="resolved">보수 완료 (Resolved)</option>
                      </select>
                    </div>
                  </div>
                  {/* Delete Button */}
                  <button
                    onClick={() => handleDeleteItem(selectedItem.id, 'hazard')}
                    style={{
                      marginTop: '12px',
                      width: '100%',
                      padding: '8px',
                      borderRadius: 'var(--ldsg-radius-200)',
                      border: '1px solid #ef4444',
                      background: 'transparent',
                      color: '#ef4444',
                      fontSize: '12px',
                      fontWeight: '600',
                      cursor: 'pointer',
                      transition: 'all 0.2s ease',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '4px'
                    }}
                    onMouseEnter={(e) => {
                      e.target.style.background = 'rgba(239, 68, 68, 0.1)';
                    }}
                    onMouseLeave={(e) => {
                      e.target.style.background = 'transparent';
                    }}
                  >
                    <Trash2 size={13} /> 이 위험 제보 삭제
                  </button>
                </>
              ) : (
                <>
                  <span className="detail-header" style={{ color: 'var(--color-safe)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <Building2 size={14} /> {selectedItem.name}
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
                  {/* Delete Button */}
                  <button
                    onClick={() => handleDeleteItem(selectedItem.id, 'building')}
                    style={{
                      marginTop: '12px',
                      width: '100%',
                      padding: '8px',
                      borderRadius: 'var(--ldsg-radius-200)',
                      border: '1px solid #ef4444',
                      background: 'transparent',
                      color: '#ef4444',
                      fontSize: '12px',
                      fontWeight: '600',
                      cursor: 'pointer',
                      transition: 'all 0.2s ease',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '4px'
                    }}
                    onMouseEnter={(e) => {
                      e.target.style.background = 'rgba(239, 68, 68, 0.1)';
                    }}
                    onMouseLeave={(e) => {
                      e.target.style.background = 'transparent';
                    }}
                  >
                    <Trash2 size={13} /> 이 건물 접근성 정보 삭제
                  </button>
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
          <div className="mobile-top-right" style={{ display: 'flex', gap: '6px' }}>
            <button 
              className="theme-toggle-btn" 
              onClick={() => setIsRightSidebarOpen(prev => !prev)}
              title="도움말 및 기준서 보기"
              aria-label="도움말 및 기준서 보기"
            >
              <BookOpen size={16} />
            </button>
            <button 
              className="theme-toggle-btn" 
              onClick={toggleTheme}
              title={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
              aria-label={theme === 'dark' ? '밝은 모드로 전환' : '어두운 모드로 전환'}
            >
              {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            </button>
            <button 
              className="theme-toggle-btn" 
              onClick={() => setIsAuthModalOpen(true)}
              title={user ? `${user.email} (로그아웃)` : '로그인 / 회원가입'}
              aria-label="로그인 / 회원가입"
            >
              <User size={16} />
            </button>
          </div>
        </div>

        <DynamicMap 
          hazards={hazards}
          buildings={buildings}
          onMapClick={handleMapClick}
          onSelectItem={handleSelectItem}
          filters={filters}
          theme={theme}
          userLocation={userLocation}
          searchLocation={searchLocation}
          heatmapMode={heatmapMode}
        />

        {/* Mobile Floating Bottom Detail Card */}
        {selectedItem && showMobileDetail && (
          <div className="mobile-detail-card glass-panel">
            <div className="mobile-detail-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                {selectedItemType === 'hazard' ? (
                  <>
                    <span className="detail-header" style={{ color: 'var(--color-warn)', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <AlertTriangle size={14} />
                      {selectedItem.type === 'step' ? '보행 단차' : 
                       selectedItem.type === 'damage' ? '노면 파손' :
                       selectedItem.type === 'obstacle' ? '보행 적치물' : '보도 급경사'}
                    </span>
                    <span className={`detail-badge ${selectedItem.severity}`}>
                      위험도 {selectedItem.severity === 'high' ? '상' : selectedItem.severity === 'medium' ? '중' : '하'}
                    </span>
                  </>
                ) : (
                  <span className="detail-header" style={{ color: 'var(--color-safe)', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <Building2 size={14} /> {selectedItem.name}
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
                  {/* Mobile status selector */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '6px', marginBottom: '4px', flexWrap: 'wrap' }}>
                    <span className={`status-badge ${selectedItem.status || 'reported'}`}>
                      {(selectedItem.status || 'reported') === 'reported' ? '접수됨' :
                       selectedItem.status === 'processing' ? '조사중' :
                       selectedItem.status === 'scheduled' ? '보수 예정' : '보수 완료'}
                    </span>
                    <select
                      className="status-select"
                      value={selectedItem.status || 'reported'}
                      onChange={(e) => handleStatusChange(selectedItem.id, e.target.value)}
                      style={{ padding: '4px 8px', fontSize: '11px' }}
                    >
                      <option value="reported">접수</option>
                      <option value="processing">조사중</option>
                      <option value="scheduled">보수 예정</option>
                      <option value="resolved">보수 완료</option>
                    </select>
                  </div>
                  <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                    제보: {new Date(selectedItem.reported_at).toLocaleString('ko-KR')}
                  </p>
                  {/* Mobile Delete Button */}
                  <button
                    onClick={() => handleDeleteItem(selectedItem.id, 'hazard')}
                    style={{
                      marginTop: '10px',
                      width: '100%',
                      padding: '6px',
                      borderRadius: 'var(--ldsg-radius-200)',
                      border: '1px solid #ef4444',
                      background: 'transparent',
                      color: '#ef4444',
                      fontSize: '11px',
                      fontWeight: '600',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '4px'
                    }}
                  >
                    <Trash2 size={13} /> 이 위험 제보 삭제
                  </button>
                </>
              ) : (
                <>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px 8px', fontSize: '11px', marginTop: '2px' }}>
                    <div><strong>경사로:</strong> {selectedItem.has_ramp ? `설치 (${selectedItem.ramp_slope_degree || '?'}°)` : '미설치'}</div>
                    <div><strong>승강기:</strong> {selectedItem.has_elevator ? '있음' : '없음'}</div>
                    <div><strong>출입문:</strong> {selectedItem.main_entrance_type === 'automatic' ? '자동문' : selectedItem.main_entrance_type === 'revolving' ? '회전문' : '여닫이문'}</div>
                    <div><strong>화장실:</strong> {selectedItem.disabled_toilet ? '장애인용' : '일반'}</div>
                  </div>
                  {/* Mobile Delete Button */}
                  <button
                    onClick={() => handleDeleteItem(selectedItem.id, 'building')}
                    style={{
                      marginTop: '10px',
                      width: '100%',
                      padding: '6px',
                      borderRadius: 'var(--ldsg-radius-200)',
                      border: '1px solid #ef4444',
                      background: 'transparent',
                      color: '#ef4444',
                      fontSize: '11px',
                      fontWeight: '600',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '4px'
                    }}
                  >
                    <Trash2 size={13} /> 건물 정보 삭제
                  </button>
                </>
              )}
            </div>
          </div>
        )}


      </section>

      {/* Report Form Modal */}
      <ReportModal 
        isOpen={isReportModalOpen}
        onClose={() => setIsReportModalOpen(false)}
        onSubmit={handleReportSubmit}
        latitude={clickCoords.lat}
        longitude={clickCoords.lng}
      />

      {/* Auth Login/Signup Modal */}
      <AuthModal 
        isOpen={isAuthModalOpen}
        onClose={() => setIsAuthModalOpen(false)}
        user={user}
        onAuthSuccess={(u) => setUser(u)}
      />
      {/* Right Sidebar (Help & Guidelines) */}
      <aside className={`right-sidebar glass-panel ${isRightSidebarOpen ? 'open' : ''}`}>
        <div className="right-sidebar-header">
          <span className="right-sidebar-title">
            <BookOpen size={16} color="var(--color-accent)" /> 관제 가이드 및 기준서
          </span>
          <button 
            className="mobile-sidebar-close" 
            onClick={() => setIsRightSidebarOpen(false)}
            aria-label="도움말 닫기"
            style={{ display: 'flex' }}
          >
            <X size={16} />
          </button>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '10px' }}>
          {/* Accordion 1 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(0)}>
              <h5><AlertTriangle size={14} color="var(--color-warn)" /> 노면 위험도 판단 기준</h5>
              {expandedSection === 0 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 0 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong style={{ color: 'var(--color-danger)' }}>상 (High Severity)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 3cm 이상 또는 노면 공사/파손이 심해 바퀴가 빠질 위험이 있어 휠체어 자력 통행이 불가능한 구간입니다. 우회 경로 설정이 필수적입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: 'var(--color-warn)' }}>중 (Medium Severity)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 1.5cm ~ 3cm 사이이거나 노면 요철이 불규칙하여 주행 시 충격이 크고 동반자의 일시적인 뒤떨어짐/보조가 필요한 구간입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: 'var(--color-safe)' }}>하 (Low Severity)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 1.5cm 미만으로 미세한 진동은 있으나 휠체어 단독 주행이 가능하며 경미한 주의만 요구되는 구간입니다.
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Accordion 2 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(1)}>
              <h5><Wrench size={14} color="var(--color-accent)" /> 유지보수 파이프라인</h5>
              {expandedSection === 1 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 1 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong style={{ color: '#2c7dfa' }}>접수 (Reported)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    보행 약자 앱 또는 시민 제보를 통해 도로의 단차가 시스템에 신규로 접수 및 등록된 초기 대기 상태입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#8b5cf6' }}>조사중 (Processing)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    지자체 담당 부서에서 현장 조사를 나가 실제 노면 높이 및 휠체어 진입 가능 여부를 정밀 실사 중인 상태입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#f97316' }}>보수 예정 (Scheduled)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    보도 블록 교체, 아스콘 평탄화 공사 또는 경사로 추가 설치 관련 예산 및 공사 일정이 확정되어 보수 대기 중인 상태입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#06c755' }}>보수 완료 (Resolved)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    공사가 완료되어 단차가 평탄하게 복구되었거나 장애물이 수거되어 보행 약자가 안전하게 통행할 수 있는 청정 상태입니다.
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Accordion 3 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(2)}>
              <h5><Layers size={14} color="var(--color-accent)" /> 열지도 가중치 해설</h5>
              {expandedSection === 2 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 2 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong>위험 수준별 열원 크기</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    위험 등급에 비례해 고위험(상) 제보는 80px 반경의 붉은 열원, 중위험(중)은 60px 주황색, 저위험(하)은 40px 노란색 열원을 지도 상에 생성합니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>위험 누적 핫스팟</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    여러 개의 위험 마커가 밀집된 구역은 그라데이션이 합쳐지며 농도가 매우 짙어집니다. 이 구역은 관제 우선순위 1순위로 고려됩니다.
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      </aside>
    </main>
  );
}
