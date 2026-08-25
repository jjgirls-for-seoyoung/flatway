"use client";

import { useState } from 'react';
import { X, User, Lock, Mail, LogOut } from 'lucide-react';
import { supabase } from '../lib/supabaseClient';

export default function AuthModal({ isOpen, onClose, user, onAuthSuccess }) {
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  if (!isOpen) return null;

  const handleAuth = async (e) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');
    setMessage('');

    if (!email.trim() || !password.trim()) {
      setErrorMsg('이메일과 비밀번호를 모두 입력해 주세요.');
      setLoading(false);
      return;
    }

    try {
      if (isSignUp) {
        const { error } = await supabase.auth.signUp({
          email,
          password
        });
        if (error) throw error;
        setMessage('회원가입 확인 메일이 발송되었습니다! (이메일을 확인해 주세요)');
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email,
          password
        });
        if (error) throw error;
        onAuthSuccess(data.user);
        alert('성공적으로 로그인되었습니다!');
        onClose();
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
      onClose();
    } catch (err) {
      alert(`로그아웃 실패: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay">
      <div className="modal-content glass-panel" style={{ width: '360px' }}>
        <div className="modal-header">
          <h3 className="modal-title" style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <User size={18} color="var(--color-accent)" /> 
            {user ? '계정 정보 및 관리' : isSignUp ? '새로운 계정 만들기' : '데이터베이스 로그인'}
          </h3>
          <button className="modal-close-btn" onClick={onClose} aria-label="닫기">
            <X size={20} />
          </button>
        </div>

        {user ? (
          // Logged In View
          <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', textAlign: 'center', padding: '10px 0' }}>
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '4px' }}>
              <div style={{ padding: '12px', borderRadius: '50%', background: 'rgba(6, 199, 85, 0.1)', color: 'var(--color-safe)' }}>
                <User size={36} />
              </div>
            </div>
            <p style={{ fontSize: '13px', fontWeight: '600', color: 'var(--text-primary)' }}>
              현재 로그인된 계정:
            </p>
            <p style={{ fontSize: '13px', fontWeight: 'bold', color: 'var(--color-accent)', wordBreak: 'break-all' }}>
              {user.email}
            </p>
            <button 
              onClick={handleSignOut} 
              className="btn btn-secondary"
              disabled={loading}
              style={{ 
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center', 
                gap: '6px', 
                marginTop: '10px',
                borderColor: 'var(--color-danger)',
                color: 'var(--color-danger)'
              }}
            >
              <LogOut size={14} /> 로그아웃
            </button>
          </div>
        ) : (
          // Auth Form (Login / Register Toggle)
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
            <div className="form-group">
              <label style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
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
            <div className="form-group">
              <label style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
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
              <p style={{ margin: 0, fontSize: '11px', color: 'var(--color-danger)' }}>
                {errorMsg}
              </p>
            )}

            {message && (
              <p style={{ margin: 0, fontSize: '11px', color: 'var(--color-safe)' }}>
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
                onClick={onClose}
                style={{ width: '100%', padding: '10px' }}
              >
                로컬 게스트 모드로 둘러보기
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
