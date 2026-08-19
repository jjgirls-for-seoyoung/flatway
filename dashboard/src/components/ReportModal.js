"use client";

import { useState } from 'react';
import { X } from 'lucide-react';

export default function ReportModal({
  isOpen,
  onClose,
  onSubmit,
  latitude,
  longitude
}) {
  const [type, setType] = useState('step');
  const [stepHeight, setStepHeight] = useState('3.0');
  const [severity, setSeverity] = useState('high');
  const [description, setDescription] = useState('');

  if (!isOpen) return null;

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!description.trim()) {
      alert('제보 상세 설명을 입력해 주세요.');
      return;
    }

    const report = {
      type,
      latitude,
      longitude,
      step_height_cm: type === 'step' ? parseFloat(stepHeight) : null,
      severity,
      description,
      reported_at: new Date().toISOString(),
      is_verified: false // Simulated reports are unverified by default
    };

    onSubmit(report);
    // Reset form
    setDescription('');
    onClose();
  };

  return (
    <div className="modal-overlay">
      <div className="modal-content glass-panel">
        <div className="modal-header">
          <h3 className="modal-title">🚨 실시간 노면 안전 제보하기</h3>
          <button className="modal-close-btn" onClick={onClose}>
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
          {/* Coordinates (Read-only) */}
          <div className="form-row">
            <div className="form-group">
              <label>위도 (Latitude)</label>
              <input 
                type="text" 
                className="form-control" 
                value={latitude.toFixed(6)} 
                readOnly 
                style={{ opacity: 0.6, cursor: 'not-allowed' }}
              />
            </div>
            <div className="form-group">
              <label>경도 (Longitude)</label>
              <input 
                type="text" 
                className="form-control" 
                value={longitude.toFixed(6)} 
                readOnly 
                style={{ opacity: 0.6, cursor: 'not-allowed' }}
              />
            </div>
          </div>

          {/* Hazard Type */}
          <div className="form-group">
            <label>위험 유형</label>
            <select 
              className="form-control" 
              value={type} 
              onChange={(e) => setType(e.target.value)}
            >
              <option value="step">보도 턱/단차 (Step)</option>
              <option value="damage">노면 파손/요철 (Damage)</option>
              <option value="obstacle">적치물/불법주차 (Obstacle)</option>
              <option value="slope">급경사 구간 (Slope)</option>
            </select>
          </div>

          {/* Step Height (Visible only for 'step' type) */}
          {type === 'step' && (
            <div className="form-group">
              <label>단차 높이 (cm)</label>
              <input 
                type="number" 
                step="0.1" 
                className="form-control" 
                value={stepHeight} 
                onChange={(e) => setStepHeight(e.target.value)}
                min="0"
                required
              />
            </div>
          )}

          {/* Severity */}
          <div className="form-group">
            <label>이동 약자 위험도 (심각도)</label>
            <select 
              className="form-control" 
              value={severity} 
              onChange={(e) => setSeverity(e.target.value)}
            >
              <option value="high">상 (휠체어 진입 불가능 / 우회 필수)</option>
              <option value="medium">중 (이동 곤란 / 동반자 보조 필요)</option>
              <option value="low">하 (조금 흔들리거나 주의 필요)</option>
            </select>
          </div>

          {/* Description */}
          <div className="form-group">
            <label>상세 위치 및 내용 설명</label>
            <textarea 
              className="form-control" 
              rows="3" 
              placeholder="예: 횡단보도 진입로의 턱이 높아 올라타기 어렵습니다."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              required
              style={{ resize: 'none' }}
            />
          </div>

          {/* Buttons */}
          <div className="btn-group">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              취소
            </button>
            <button type="submit" className="btn btn-primary">
              제보 등록하기
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
