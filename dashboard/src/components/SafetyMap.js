"use client";

import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import { mockRoutes } from '../data/mockData';

// Fix Leaflet marker icons using DivIcon for custom styling and reliability
const createCustomIcon = (type) => {
  let innerChar = '!';
  if (type === 'building') innerChar = '🏢';
  else if (type === 'step') innerChar = '⚠️';
  else if (type === 'damage') innerChar = '⚙️';
  else if (type === 'obstacle') innerChar = '⛔';
  else if (type === 'slope') innerChar = '▲';

  return L.divIcon({
    className: `custom-marker ${type}`,
    html: `<span style="font-size: 11px; display: flex; align-items: center; justify-content: center; height: 100%; color: white;">${innerChar}</span>`,
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
  selectedRouteMode,
  onMapClick,
  onSelectItem,
  filters,
  theme = 'dark',
  userLocation,
  searchLocation
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

  const currentRoute = mockRoutes[selectedRouteMode];

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
            icon={createCustomIcon(hazard.type)}
            eventHandlers={{
              click: () => onSelectItem(hazard, 'hazard')
            }}
          >
            <Popup>
              <div style={{ minWidth: '150px' }}>
                <span className={`detail-badge ${hazard.severity}`} style={{ marginBottom: '4px' }}>
                  {hazard.type === 'step' ? '단차' : 
                   hazard.type === 'damage' ? '노면 파손' :
                   hazard.type === 'obstacle' ? '적치물 장애물' : '급경사'} ({hazard.severity === 'high' ? '상' : hazard.severity === 'medium' ? '중' : '하'})
                </span>
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

        {/* Draw Safe/Recommended Route Line */}
        {currentRoute && (
          <Polyline
            positions={currentRoute.coordinates}
            color={currentRoute.color}
            weight={6}
            opacity={0.85}
            lineCap="round"
          >
            <Popup>
              <div style={{ minWidth: '150px' }}>
                <h4 style={{ margin: '0 0 4px 0', fontSize: '13px', color: currentRoute.color, fontWeight: '700' }}>
                  {currentRoute.name}
                </h4>
                <p style={{ margin: '2px 0', fontSize: '12px', fontWeight: '600', color: 'var(--text-primary)' }}>
                  거리: {currentRoute.distance} | 소요시간: {currentRoute.time}
                </p>
                <p style={{ margin: 0, fontSize: '11px', color: 'var(--text-secondary)', borderTop: '1px solid var(--glass-border)', paddingTop: '4px', marginTop: '4px' }}>
                  {currentRoute.notes}
                </p>
              </div>
            </Popup>
          </Polyline>
        )}

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
