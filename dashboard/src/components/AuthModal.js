"use client";

import { useState, useEffect } from 'react';
import { X, User, Lock, Mail, LogOut, ArrowLeft } from 'lucide-react';
import { supabase } from '../lib/supabaseClient';

export default function AuthModal({ isOpen, onClose, user, onAuthSuccess, usingSupabase }) {
  const [view, setView] = useState('settings'); // 'settings' or 'login'
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  // Local switch toggle for location tracking (simulating map preference in local storage)
  const [locationTracking, setLocationTracking] = useState(true);

  // Sync state with open status
  useEffect(() => {
    if (isOpen) {
      setView('settings');
      setErrorMsg('');
      setMessage('');
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleAuth = async (e) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');
    setMessage('');

    const sanitizedEmail = email.trim().toLowerCase();
    const sanitizedPassword = password.trim();

    if (!sanitizedEmail || !sanitizedPassword) {
      setErrorMsg('이메일과 비밀번호를 모두 입력해 주세요.');
      setLoading(false);
      return;
    }

    try {
      if (isSignUp) {
        const { error } = await supabase.auth.signUp({
          email: sanitizedEmail,
          password: sanitizedPassword
        });
        if (error) throw error;
        setMessage('회원가입 완료! (SMTP 상태에 따라 인증 메일 확인이 필요할 수 있습니다)');
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email: sanitizedEmail,
          password: sanitizedPassword
        });
        if (error) throw error;
        onAuthSuccess(data.user);
        alert('성공적으로 로그인되었습니다!');
        setView('settings');
      }
    } catch (err) {
      setErrorMsg(err.message || '인증 과정 중 오류가 발생했습니다.');
    } finally {
      setLoading(false);
    }
  };

  const handleSignOut = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      onAuthSuccess(null);
      alert('성공적으로 로그아웃되었습니다.');
    } catch (err) {
      alert(`로그아웃 실패: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay">
      <div className="modal-content glass-panel" style={{ width: '400px', maxWidth: '90vw', padding: '24px' }}>
        
        {/* Header */}
        <div className="modal-header" style={{ marginBottom: '16px' }}>
          <div style={{ textAlign: 'left' }}>
            <h3 className="modal-title" style={{ fontSize: '19px', fontWeight: '700', color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '6px' }}>
              {view === 'login' ? (
                <>
                  <button 
                    onClick={() => { setView('settings'); setErrorMsg(''); setMessage(''); }}
                    style={{ background: 'transparent', border: 'none', color: 'var(--text-secondary)', padding: 0, cursor: 'pointer', display: 'flex', alignItems: 'center' }}
                    aria-label="뒤로 가기"
                  >
                    <ArrowLeft size={16} />
                  </button>
                  {isSignUp ? '새로운 계정 만들기' : '데이터베이스 로그인'}
                </>
              ) : (
                '계정 설정'
              )}
            </h3>
            {view === 'settings' && (
              <p style={{ margin: '2px 0 0 0', fontSize: '13px', color: 'var(--text-secondary)' }}>
                일반 기본 환경설정 및 관리자 계정 권한을 관리합니다.
              </p>
            )}
          </div>
          <button className="modal-close-btn" onClick={onClose} aria-label="닫기">
            <X size={20} />
          </button>
        </div>

        {/* View content */}
        {view === 'settings' ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            
            {/* General Settings Section */}
            <div className="settings-section">
              <h4 className="settings-section-title">일반 설정</h4>
              
              {/* Sync Row */}
              <div className="settings-row">
                <div className="settings-row-info">
                  <span className="settings-row-title">실시간 데이터 동기화</span>
                  <span className="settings-row-desc">
                    지도 데이터와 Supabase 데이터베이스를 실시간으로 양방향 동기화합니다.
                  </span>
                </div>
                <div 
                  className="switch-container" 
                  onClick={() => {
                    if (!supabase) {
                      alert('Supabase가 활성화되어 있지 않아 실시간 동기화를 켤 수 없습니다. (환경 설정 확인 필요)');
                      return;
                    }
                    onToggleSync(!usingSupabase);
                  }}
                >
                  <div className={`switch-track ${usingSupabase ? 'active' : ''}`}>
                    <div className="switch-thumb"></div>
                  </div>
                </div>
              </div>

              {/* Location Tracking Row */}
              <div className="settings-row">
                <div className="settings-row-info">
                  <span className="settings-row-title">자동 현재 위치 추적</span>
                  <span className="settings-row-desc">
                    GPS 센서를 활용하여 실시간으로 사용자의 위치를 추적하고 지도 상에 반영합니다.
                  </span>
                </div>
                <div className="switch-container" onClick={() => setLocationTracking(!locationTracking)}>
                  <div className={`switch-track ${locationTracking ? 'active' : ''}`}>
                    <div className="switch-thumb"></div>
                  </div>
                </div>
              </div>
            </div>

            {/* Account Info Section */}
            <div className="settings-section" style={{ marginTop: '4px' }}>
              <h4 className="settings-section-title">계정 및 권한</h4>
              
              {/* Plan Row */}
              <div className="settings-row">
                <div className="settings-row-info">
                  <span className="settings-row-title">
                    관제 권한 등급: {user ? '최고 관리자' : '게스트 관찰자'}
                  </span>
                  <span className="settings-row-desc">
                    {user ? '실시간 위험 요소 데이터베이스 삭제 및 유지보수 파이프라인 수정 권한이 활성화되었습니다.' : '지도 조회 및 위치 검색 전용 세션입니다. 제보 삭제 및 진행 상태 수정 권한이 제한됩니다.'}
                  </span>
                </div>
              </div>

              {/* Email & Auth Actions Row */}
              <div className="settings-row">
                <div className="settings-row-info">
                  <span className="settings-row-title">로그인 이메일</span>
                  <span className="settings-row-desc" style={{ wordBreak: 'break-all', fontWeight: user ? '600' : 'normal' }}>
                    {user ? user.email : '로그인 정보 없음'}
                  </span>
                </div>
                {user ? (
                  <button 
                    className="btn btn-secondary" 
                    style={{ fontSize: '10.5px', padding: '6px 12px', height: 'auto', borderColor: 'var(--glass-border)', color: 'var(--text-primary)' }}
                    onClick={handleSignOut}
                    disabled={loading}
                  >
                    로그아웃
                  </button>
                ) : (
                  <button 
                    className="btn btn-secondary" 
                    style={{ fontSize: '10.5px', padding: '6px 12px', height: 'auto', borderColor: 'var(--glass-border)', color: 'var(--text-primary)' }}
                    onClick={() => { setView('login'); setIsSignUp(false); }}
                  >
                    로그인
                  </button>
                )}
              </div>

            </div>



          </div>
        ) : (
          // Auth Form view
          <form onSubmit={handleAuth} style={{ display: 'flex', flexDirection: 'column', gap: '14px', marginTop: '4px' }}>
            {/* Tab Selector */}
            <div style={{ display: 'flex', borderBottom: '1px solid var(--glass-border)', marginBottom: '4px' }}>
              <button
                type="button"
                onClick={() => { setIsSignUp(false); setErrorMsg(''); setMessage(''); }}
                style={{
                  flex: 1,
                  padding: '10px',
                  background: 'transparent',
                  border: 'none',
                  borderBottom: !isSignUp ? '2px solid var(--color-accent)' : 'none',
                  color: !isSignUp ? 'var(--text-primary)' : 'var(--text-secondary)',
                  fontWeight: !isSignUp ? 'bold' : 'normal',
                  fontSize: '12px',
                  cursor: 'pointer'
                }}
              >
                로그인
              </button>
              <button
                type="button"
                onClick={() => { setIsSignUp(true); setErrorMsg(''); setMessage(''); }}
                style={{
                  flex: 1,
                  padding: '10px',
                  background: 'transparent',
                  border: 'none',
                  borderBottom: isSignUp ? '2px solid var(--color-accent)' : 'none',
                  color: isSignUp ? 'var(--text-primary)' : 'var(--text-secondary)',
                  fontWeight: isSignUp ? 'bold' : 'normal',
                  fontSize: '12px',
                  cursor: 'pointer'
                }}
              >
                회원가입
              </button>
            </div>

            {/* Email */}
            <div className="form-group" style={{ textAlign: 'left' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11px', fontWeight: '700', marginBottom: '4px' }}>
                이메일 주소
              </label>
              <input
                type="email"
                className="form-control"
                placeholder="name@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>

            {/* Password */}
            <div className="form-group" style={{ textAlign: 'left' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11px', fontWeight: '700', marginBottom: '4px' }}>
                비밀번호
              </label>
              <input
                type="password"
                className="form-control"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>

            {errorMsg && (
              <p style={{ margin: 0, fontSize: '11px', color: 'var(--color-danger)', textAlign: 'left' }}>
                {errorMsg}
              </p>
            )}

            {message && (
              <p style={{ margin: 0, fontSize: '11px', color: 'var(--color-safe)', textAlign: 'left' }}>
                {message}
              </p>
            )}

            {/* Submit Buttons */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '6px' }}>
              <button 
                type="submit" 
                className="btn btn-primary"
                disabled={loading}
                style={{ width: '100%', padding: '10px' }}
              >
                {loading ? '처리 중...' : isSignUp ? '가입하기' : '로그인 완료'}
              </button>
              
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setView('settings')}
                style={{ width: '100%', padding: '10px' }}
              >
                취소 및 뒤로가기
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
