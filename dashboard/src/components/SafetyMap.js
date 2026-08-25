"use client";

import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import { mockRoutes } from '../data/mockData';

// Fix Leaflet marker icons using DivIcon for custom styling and reliability
const createCustomIcon = (type) => {
  let innerHtml = '';
  if (type === 'building') {
    innerHtml = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18Z"/><path d="M6 12H4a2 2 0 0 0-2 2v8"/><path d="M18 16h2a2 2 0 0 1 2 2v4"/><path d="M10 6h4"/><path d="M10 10h4"/><path d="M10 14h4"/><path d="M10 18h4"/></svg>`;
  } else if (type === 'step') {
    innerHtml = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`;
  } else if (type === 'damage') {
    innerHtml = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>`;
  } else if (type === 'obstacle') {
    innerHtml = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>`;
  } else if (type === 'slope') {
    innerHtml = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m3 16 13-10 5 10H3z"/></svg>`;
  }

  return L.divIcon({
    className: `custom-marker ${type}`,
    html: `<span style="display: flex; align-items: center; justify-content: center; height: 100%; color: white;">${innerHtml}</span>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
    popupAnchor: [0, -14]
  });
};

const createUserLocationIcon = () => {
  return L.divIcon({
    className: 'user-location-marker',
    html: '<div class="pulse-ring"></div><div class="pulse-dot"></div>',
    iconSize: [30, 30],
    iconAnchor: [15, 15]
  });
};

const createHeatmapIcon = () => {
  return L.divIcon({
    className: 'heatmap-circle',
    html: '',
    iconSize: [80, 80],
    iconAnchor: [40, 40]
  });
};

function MapViewCenter({ userLocation, searchLocation }) {
  const map = useMap();
  useEffect(() => {
    if (searchLocation) {
      map.flyTo(searchLocation, 16, { animate: true, duration: 1.5 });
    }
  }, [searchLocation]);

  useEffect(() => {
    if (userLocation && !searchLocation) {
      map.flyTo(userLocation, 17, { animate: true, duration: 1.5 });
    }
  }, [userLocation]);
  return null;
}

// Map event handler to capture click coordinates for report simulator
function MapClickHandler({ onMapClick }) {
  useMapEvents({
    click(e) {
      // Prevent click event trigger if clicking on an interactive marker/popup
      onMapClick(e.latlng.lat, e.latlng.lng);
    }
  });
  return null;
}

export default function SafetyMap({
  hazards,
  buildings,
  onMapClick,
  onSelectItem,
  filters,
  theme = 'dark',
  userLocation,
  searchLocation,
  heatmapMode = false
}) {
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
  }, []);

  if (!isMounted) return <div style={{ height: '100%', background: 'var(--bg-primary)' }} />;

  // Initial center: Jakjeon Station [37.5346, 126.7225]
  const center = [37.5360, 126.7230]; 

  // Filtered lists
  const showStep = filters.step;
  const showDamage = filters.damage;
  const showBuilding = filters.building;

  const filteredHazards = hazards.filter(h => {
    if (h.type === 'step' && showStep) return true;
    if ((h.type === 'damage' || h.type === 'obstacle' || h.type === 'slope') && showDamage) return true;
    return false;
  });

  const filteredBuildings = buildings.filter(() => showBuilding);

  return (
    <div className={`map-container ${theme === 'dark' ? 'dark-theme-map' : 'light-theme-map'}`}>
      <MapContainer 
        center={center} 
        zoom={16} 
        scrollWheelZoom={true}
        style={{ width: '100%', height: '100%' }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* Render Hazards */}
        {filteredHazards.map((hazard) => (
          <Marker
            key={hazard.id}
            position={[hazard.latitude, hazard.longitude]}
            icon={heatmapMode ? createHeatmapIcon() : createCustomIcon(hazard.type)}
            eventHandlers={{
              click: heatmapMode ? undefined : () => onSelectItem(hazard, 'hazard')
            }}
          >
            {!heatmapMode && (
              <Popup>
                <div style={{ minWidth: '160px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px', gap: '6px' }}>
                    <span className={`detail-badge ${hazard.severity}`}>
                      {hazard.type === 'step' ? '단차' : 
                       hazard.type === 'damage' ? '노면 파손' :
                       hazard.type === 'obstacle' ? '적치물' : '급경사'} ({hazard.severity === 'high' ? '상' : hazard.severity === 'medium' ? '중' : '하'})
                    </span>
                    <span className={`status-badge ${hazard.status || 'reported'}`} style={{ transform: 'scale(0.85)', transformOrigin: 'right' }}>
                      {(hazard.status || 'reported') === 'reported' ? '접수' :
                       hazard.status === 'processing' ? '조사중' :
                       hazard.status === 'scheduled' ? '보수예정' : '보수완료'}
                    </span>
                  </div>
                  <h4 style={{ margin: '4px 0', fontSize: '13px', fontWeight: '600', color: 'var(--text-primary)' }}>
                    {hazard.step_height_cm ? `${hazard.step_height_cm}cm 단차 위험` : '노면 안전 위험'}
                  </h4>
                  <p style={{ margin: 0, fontSize: '11px', color: 'var(--text-secondary)' }}>
                    {hazard.description}
                  </p>
                  <div style={{ fontSize: '9px', color: 'var(--text-muted)', marginTop: '6px' }}>
                    제보: {new Date(hazard.reported_at).toLocaleString('ko-KR')}
                  </div>
                </div>
              </Popup>
            )}
          </Marker>
        ))}

        {/* Render Buildings */}
        {filteredBuildings.map((bldg) => (
          <Marker
            key={bldg.id}
            position={[bldg.latitude, bldg.longitude]}
            icon={createCustomIcon('building')}
            eventHandlers={{
              click: () => onSelectItem(bldg, 'building')
            }}
          >
            <Popup>
              <div style={{ minWidth: '160px' }}>
                <span className="detail-badge" style={{ background: 'rgba(16, 185, 129, 0.15)', color: 'var(--color-safe)', marginBottom: '4px' }}>
                  건물 접근성 정보
                </span>
                <h4 style={{ margin: '4px 0', fontSize: '13px', fontWeight: '700', color: 'var(--text-primary)' }}>
                  {bldg.name}
                </h4>
                <p style={{ margin: '2px 0', fontSize: '11px', color: 'var(--text-primary)' }}>
                  - 경사로: {bldg.has_ramp ? `설치 완료 (${bldg.ramp_slope_degree || '?'}°)` : '미설치 (계단만 있음)'}
                </p>
                <p style={{ margin: '2px 0', fontSize: '11px', color: 'var(--text-primary)' }}>
                  - 엘리베이터: {bldg.has_elevator ? '있음' : '없음'}
                </p>
                <p style={{ margin: '2px 0', fontSize: '11px', color: 'var(--text-primary)' }}>
                  - 주출입구: {bldg.main_entrance_type === 'automatic' ? '자동문' : bldg.main_entrance_type === 'revolving' ? '회전문' : '여닫이문'}
                </p>
              </div>
            </Popup>
          </Marker>
        ))}



        {/* Render User Current Location if available */}
        {userLocation && (
          <Marker position={userLocation} icon={createUserLocationIcon()}>
            <Popup>
              <div style={{ fontSize: '11px', fontWeight: 'bold', textAlign: 'center', color: 'var(--text-primary)' }}>
                현재 내 위치 (GPS)
              </div>
            </Popup>
          </Marker>
        )}

        {/* Center map view to User Location when updated */}
        <MapViewCenter userLocation={userLocation} searchLocation={searchLocation} />

        {/* Capture click on map for simulator */}
        <MapClickHandler onMapClick={onMapClick} />
      </MapContainer>
    </div>
  );
}
