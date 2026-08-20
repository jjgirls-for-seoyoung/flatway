import dynamic from 'next/dynamic';

const DynamicMap = dynamic(
  () => import('./SafetyMap'),
  {
    ssr: false,
    loading: () => (
      <div 
        style={{ 
          height: '100%', 
          width: '100%',
          background: 'var(--bg-primary)', 
          display: 'flex', 
          flexDirection: 'column',
          alignItems: 'center', 
          justifyContent: 'center', 
          color: 'var(--text-secondary)',
          fontFamily: 'var(--font-sans)',
          gap: '12px'
        }}
      >
        <div style={{
          width: '40px',
          height: '40px',
          border: '3px solid var(--bg-tertiary)',
          borderTop: '3px solid var(--color-accent)',
          borderRadius: '50%',
          animation: 'spin 1s linear infinite'
        }}></div>
        <span>실시간 지도 데이터 준비 중...</span>
        <style dangerouslySetInnerHTML={{__html: `
          @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
        `}} />
      </div>
    )
  }
);

export default DynamicMap;
