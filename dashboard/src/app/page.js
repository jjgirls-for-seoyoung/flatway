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
  const [expandedDetails, setExpandedDetails] = useState({});

  const toggleAccordion = (idx) => {
    setExpandedSection(expandedSection === idx ? null : idx);
  };

  const toggleDetail = (idx) => {
    setExpandedDetails(prev => ({
      ...prev,
      [idx]: !prev[idx]
    }));
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
    obstacle: true,
    slope: true,
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

  // Helper to get pin color matching hazard type
  const getHazardColor = (type) => {
    switch (type) {
      case 'step':
        return 'var(--color-danger)'; // Red for step (단차)
      case 'damage':
        return 'var(--color-warn)'; // Orange for damage (파손)
      case 'obstacle':
        return '#8b5cf6'; // Purple for obstacle (적치물)
      case 'slope':
        return '#06b6d4'; // Cyan for slope (급경사)
      default:
        return 'var(--color-warn)';
    }
  };

  // Helper to check admin permission
  const checkIsAdmin = (u) => {
    if (!u) return false;
    const isEmailAdmin = u.email?.toLowerCase().trim() === 'bugye6816@gmail.com';
    const isRoleAdmin = u.user_metadata?.role === 'admin' || u.app_metadata?.role === 'admin';
    return Boolean(isEmailAdmin || isRoleAdmin);
  };

  // 5-2. Handle Maintenance Status Change
  const handleStatusChange = async (id, newStatus) => {
    // Check admin permission
    const isAdmin = checkIsAdmin(user);
    if (!isAdmin) {
      alert('유지보수 상태 수정 권한이 없습니다. 관리자 계정으로 로그인해 주세요.');
      return;
    }

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
    // Check admin permission
    const isAdmin = checkIsAdmin(user);
    if (!isAdmin) {
      alert('삭제 권한이 없습니다. 관리자 계정으로 로그인해 주세요.');
      return;
    }

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
  const activeDamageCount = hazards.filter(h => h.type === 'damage').length;
  const activeObstacleCount = hazards.filter(h => h.type === 'obstacle').length;
  const activeSlopeCount = hazards.filter(h => h.type === 'slope').length;
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

  const isAdmin = checkIsAdmin(user);

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
                background: 'var(--bg-tertiary)',
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

        {/* Stats Grid with Total Hazards & Heatmap Control */}
        <div className="stats-grid" style={{ marginBottom: '8px' }}>
          <div className="stat-card">
            <div className="stat-header">
              <span style={{ fontSize: '11px' }}>총 노면 위험</span>
              <AlertTriangle size={14} color="var(--color-warn)" />
            </div>
            <div className="stat-value">{totalHazards}건</div>
          </div>
          
          <div className="stat-card">
            <div className="stat-header">
              <span style={{ fontSize: '11px' }}>히트맵</span>
              <Eye size={14} color="var(--color-accent)" />
            </div>
            <div className="stat-value" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '18px', lineHeight: '1.2' }}>
              <span>{heatmapMode ? 'ON' : 'OFF'}</span>
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
            <Wrench size={12} color="var(--color-accent)" /> 유지보수 현황
          </h4>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '6px', textAlign: 'center' }}>
            <div style={{ background: 'rgba(44, 125, 250, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(44, 125, 250, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>접수</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#2c7dfa' }}>{reportedCount}</div>
            </div>
            <div style={{ background: 'rgba(99, 102, 241, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(99, 102, 241, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>조사중</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#6366f1' }}>{processingCount}</div>
            </div>
            <div style={{ background: 'rgba(234, 179, 8, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(234, 179, 8, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>보수예정</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#eab308' }}>{scheduledCount}</div>
            </div>
            <div style={{ background: 'rgba(20, 184, 166, 0.1)', padding: '6px 2px', borderRadius: 'var(--ldsg-radius-200)', border: '1px solid rgba(20, 184, 166, 0.2)' }}>
              <div style={{ fontSize: '9px', color: 'var(--text-secondary)' }}>완료</div>
              <div style={{ fontSize: '13px', fontWeight: '700', color: '#14b8a6' }}>{resolvedCount}</div>
            </div>
          </div>
        </div>





        {/* Filter Panel */}
        <div className="control-panel">
          <h4 className="section-title">
            <Layers size={12} /> 필터
          </h4>
          <div className="filter-group">
            {/* 1. 단차 */}
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

            {/* 2. 파손 */}
            <div className="filter-item" onClick={() => toggleFilter('damage')}>
              <div className="filter-label-group">
                <span className="filter-dot damage" />
                <span>노면 파손 노출 ({activeDamageCount}개)</span>
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

            {/* 3. 적치물 */}
            <div className="filter-item" onClick={() => toggleFilter('obstacle')}>
              <div className="filter-label-group">
                <span className="filter-dot obstacle" />
                <span>보행 적치물 노출 ({activeObstacleCount}개)</span>
              </div>
              <label className="switch" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={filters.obstacle} 
                  onChange={() => toggleFilter('obstacle')} 
                />
                <span className="slider" />
              </label>
            </div>

            {/* 4. 경사 */}
            <div className="filter-item" onClick={() => toggleFilter('slope')}>
              <div className="filter-label-group">
                <span className="filter-dot slope" />
                <span>보도 급경사 노출 ({activeSlopeCount}개)</span>
              </div>
              <label className="switch" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={filters.slope} 
                  onChange={() => toggleFilter('slope')} 
                />
                <span className="slider" />
              </label>
            </div>

            {/* 5. 접근성 건물 */}
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
                    <span className="detail-header" style={{ color: getHazardColor(selectedItem.type), display: 'flex', alignItems: 'center', gap: '4px' }}>
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
                        disabled={!isAdmin}
                      >
                        <option value="reported">접수 (Reported)</option>
                        <option value="processing">조사중 (Processing)</option>
                        <option value="scheduled">보수 예정 (Scheduled)</option>
                        <option value="resolved">보수 완료 (Resolved)</option>
                      </select>
                    </div>
                  </div>
                  {/* Delete Button */}
                  {isAdmin && (
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
                  )}
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
                  {isAdmin && (
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
                  )}
                </>
              )}
            </div>
          ) : (
            <div className="detail-panel-empty">
              지도 위의 핀을 탭하시면 해당하는 상세 현황을 여기에서 확인하실 수 있습니다.
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
                    <span className="detail-header" style={{ color: getHazardColor(selectedItem.type), fontSize: '13px', display: 'flex', alignItems: 'center', gap: '4px' }}>
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
                      disabled={!isAdmin}
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
                  {isAdmin && (
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
                  )}
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
                  {isAdmin && (
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
                  )}
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
        usingSupabase={usingSupabase}
        onToggleSync={setUsingSupabase}
      />
      {/* Right Sidebar (Help & Guidelines) */}
      <aside className={`right-sidebar glass-panel ${isRightSidebarOpen ? 'open' : ''}`}>
        <div className="right-sidebar-header">
          <span className="right-sidebar-title">
            <BookOpen size={16} color="var(--color-accent)" /> 이용 가이드 및 기준서
          </span>
          <button 
            className="modal-close-btn" 
            onClick={() => setIsRightSidebarOpen(false)}
            aria-label="도움말 닫기"
            style={{ display: 'flex', padding: '4px' }}
          >
            <X size={18} />
          </button>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '10px' }}>
          {/* Accordion 1 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(0)}>
              <h5><AlertTriangle size={14} color="var(--color-accent)" /> 노면 위험도 기준 (상·중·하)</h5>
              {expandedSection === 0 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 0 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong style={{ color: 'var(--color-danger)' }}>상 (매우 위험)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 3cm 이상 또는 심한 도로 파손. 휠체어/유모차 단독 주행이 불가능하여 반드시 안전한 길로 돌아가야(우회) 하는 구간입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: 'var(--color-warn)' }}>중 (주의 필요)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 1.5cm~3cm, 덜컹거리는 보도블록, 급경사. 바퀴 충격이 크고 이동이 불편해 동반자의 보조가 권장됩니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: 'var(--color-safe)' }}>하 (경미함)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차 1.5cm 미만의 완만한 턱이나 작은 흠집. 휠체어가 혼자서도 안전하게 통행할 수 있는 수준입니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(0)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[0] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[0] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[0] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>단차 높이:</strong> 상(≥3.0cm), 중(1.5cm~2.9cm), 하(&lt;1.5cm)</div>
                    <div>• <strong>도로 함몰/요철:</strong> 상(≥5.0cm 포트홀), 중(2.0cm~4.9cm)</div>
                    <div>• <strong>종단 경사도:</strong> 상(&gt;12°), 중(8°~12°), 하(&lt;8°)</div>
                    <div style={{ marginTop: '4px', fontSize: '9.5px', color: 'var(--text-muted)' }}>* 장애인 편의증진법 시행규칙 및 교통약자법 기준 준용</div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Accordion 2 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(1)}>
              <h5><Wrench size={14} color="var(--color-accent)" /> 보수 처리 진행 단계</h5>
              {expandedSection === 1 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 1 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong style={{ color: '#2c7dfa' }}>접수</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    시민 또는 현장 앱을 통해 위험 요소(턱/파손)의 위치와 내용이 신규 등록된 초기 상태입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#6366f1' }}>조사중</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    안전 점검 담당자가 현장 위험도를 확인하고 수리 계획을 검토 중인 단계입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#eab308' }}>보수 예정</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    턱 완화 경사판 설치나 보도블록 교체 등 보수 공사 일정이 확정된 상태입니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong style={{ color: '#14b8a6' }}>보수 완료</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    공사가 완료되어 턱이 완만해지고 평탄하게 복구되어 누구나 안전하게 통행할 수 있는 상태입니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(1)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[1] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[1] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[1] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>접수 처리:</strong> GPS 오차 ±5m 이내 기록, 실시간 DB 전송(&lt;0.5초)</div>
                    <div>• <strong>현장 조사:</strong> 접수 후 24~48시간 이내 실사단 현장 방문 및 위험도 판정</div>
                    <div>• <strong>보수 예정:</strong> 예산 편성 및 공사 발주 승인(평균 7~14일 소요 목표)</div>
                    <div>• <strong>시공 완료:</strong> 단차 0.5cm 이하 완화 시공, 평탄성 검측 완료 및 마커 갱신</div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Accordion 3 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(2)}>
              <h5><Navigation size={14} color="var(--color-accent)" /> 추천 안전 경로 & 우회 안내</h5>
              {expandedSection === 2 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 2 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong>보행 약자 맞춤 우회</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    계단, 높은 턱(3cm 이상), 급경사 구간을 자동으로 피하고 가장 평탄하고 안전한 길로 안내합니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>이동 모드별 맞춤 경로</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    일반 보행, 수동 휠체어, 전동 휠체어 등 이동 수단에 맞춰 최적화된 도로를 추천합니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>실시간 길안내</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    경로 검색 후 상단 카드에서 다음 회전 방향과 남은 거리를 차례대로 확인하며 이동할 수 있습니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(2)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[2] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[2] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[2] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>우회 가중치:</strong> 고위험(상) 반경 15m 내 통과 회피 계수 ×10.0, 중위험 ×3.0</div>
                    <div>• <strong>경사도 제한:</strong> 휠체어 모드 탐색 시 법정 허용 경사도 4.76°(1/12) 이하 우선 배정</div>
                    <div>• <strong>턴바이턴 계산:</strong> 교차로 진입 10m 전방 회전 및 잔여 거리 안내</div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Accordion 4 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(3)}>
              <h5><Building2 size={14} color="var(--color-accent)" /> 건물 입구 편의시설 안내</h5>
              {expandedSection === 3 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 3 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong>진입 경사로</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    계단 옆에 휠체어/유모차용 경사판이 있는지 표시합니다. (경사각이 완만할수록 오르기 쉽습니다.)
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>승강기 (엘리베이터)</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    휠체어 탑승이 가능한 전용 승강기 설치 여부를 확인합니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>출입문 형태</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    자동문, 회전문, 수동 여닫이문 여부를 안내합니다. (버튼식 자동문이 가장 진입하기 편리합니다.)
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>장애인 화장실</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    휠체어 회전 공간과 안전 손잡이가 갖춰진 전용 화장실 유무를 표시합니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(3)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[3] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[3] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[3] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>경사로 규격:</strong> 유효폭 ≥1.2m, 기울기 ≤1/12(완화 시 1/8), 높이 0.75m마다 1.5m×1.5m 참 설치</div>
                    <div>• <strong>승강기 규격:</strong> 출입문 유효폭 ≥0.9m, 내부 1.6m×1.35m 이상(휠체어 회전반경 1.4m)</div>
                    <div>• <strong>출입문 규격:</strong> 통과 유효폭 ≥0.9m, 바닥 단차 ≤2.0cm</div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Accordion 5 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(4)}>
              <h5><Layers size={14} color="var(--color-accent)" /> 위험 밀집 지역 (히트맵)</h5>
              {expandedSection === 4 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 4 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong>붉은색 집중 구역</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    단차나 도로 파손 제보가 한곳에 많이 몰려 있는 지역으로, 주행 시 각별한 주의가 필요합니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>히트맵 활용 팁</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    지도 좌측 필터에서 [위험 밀집도 (히트맵)]을 켜면 피해야 할 위험 구역이나 우선 수리 지역을 한눈에 확인할 수 있습니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(4)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[4] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[4] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[4] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>열원 규모:</strong> 상(반경 80px), 중(반경 60px), 하(반경 40px)</div>
                    <div>• <strong>핫스팟 클러스터:</strong> 반경 50m 내 제보 3건 이상 누적 시 붉은색 고밀도 경고 클러스터 형성 (밀도 계수 ≥0.75)</div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Accordion 6 */}
          <div className="accordion-item">
            <div className="accordion-header" onClick={() => toggleAccordion(5)}>
              <h5><MapPin size={14} color="var(--color-accent)" /> 실시간 제보 참여 방법</h5>
              {expandedSection === 5 ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            </div>
            {expandedSection === 5 && (
              <div className="accordion-content">
                <div className="accordion-sub-item">
                  <strong>지도 클릭으로 간편 제보</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    지도에서 높은 턱이나 파손을 발견한 위치를 마우스로 클릭하면 바로 제보창이 열립니다.
                  </p>
                </div>
                <div className="accordion-sub-item" style={{ marginTop: '8px' }}>
                  <strong>실시간 지도 반영</strong>
                  <p style={{ marginTop: '2px', color: 'var(--text-secondary)' }}>
                    위험 유형과 간단한 설명을 적어 [등록]을 누르면 즉시 지도 마커와 안전 점수 통계에 반영됩니다.
                  </p>
                </div>

                {/* Detail Toggle */}
                <button 
                  type="button" 
                  onClick={() => toggleDetail(5)} 
                  style={{ marginTop: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', fontSize: '11px', fontWeight: '500', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', gap: '3px' }}
                >
                  {expandedDetails[5] ? '자세히 닫기' : '자세히'}
                  {expandedDetails[5] ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </button>
                {expandedDetails[5] && (
                  <div style={{ marginTop: '8px', padding: '10px', borderRadius: 'var(--ldsg-radius-200)', background: 'var(--bg-secondary)', border: '1px dashed var(--glass-border)', fontSize: '10.5px', color: 'var(--text-secondary)', lineHeight: '1.6' }}>
                    <div>• <strong>좌표 정밀도:</strong> OpenStreetMap WGS84 좌표계 소수점 6자리 (약 0.11m 정밀도)</div>
                    <div>• <strong>동기화 속도:</strong> Supabase PostGIS 지리 공간 인덱스 기반 실시간 동기화 (&lt;0.3초)</div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Contact info at bottom */}
        <div style={{ marginTop: 'auto', paddingTop: '16px', borderTop: '1px solid var(--glass-border)', textAlign: 'center' }}>
          <p style={{ margin: 0, fontSize: '10.5px', color: 'var(--text-muted)', letterSpacing: '0.02em' }}>
            CONTACT: kbm92343025@gmail.com
          </p>
        </div>
      </aside>
    </main>
  );
}
