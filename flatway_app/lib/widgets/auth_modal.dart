import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// 이메일 인증 코드(OTP) 로그인.
/// 비밀번호 없이 이메일로 받은 코드를 입력하면 로그인된다.
/// 로그인하지 않아도 게스트(익명) 상태로 모든 기능을 쓸 수 있다.
class AuthModal extends StatefulWidget {
  final VoidCallback onAuthChanged;

  const AuthModal({
    super.key,
    required this.onAuthChanged,
  });

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> {
  /// 이메일 코드 로그인 사용 여부.
  /// Supabase 커스텀 SMTP(코드 메일 템플릿)를 연결한 뒤 true 로 바꾼다.
  static const _emailLoginEnabled = false;

  static const _resendCooldownSeconds = 60;

  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  bool _codeSent = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  String? _errorMessage;
  String? _successMessage;

  User? get _currentUser => SupabaseService.client.auth.currentUser;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  String _friendlyError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('rate limit') || e.statusCode == '429') {
      return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (msg.contains('expired') || msg.contains('invalid')) {
      return '코드가 올바르지 않거나 만료되었습니다. 다시 확인하거나 코드를 새로 받아 주세요.';
    }
    return e.message;
  }

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await SupabaseService.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _codeController.clear();
        _successMessage = '$email 로 인증 코드를 보냈습니다. 메일함(스팸함 포함)을 확인해 주세요.';
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '코드 전송 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!_codeFormKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();
    final code = _codeController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await SupabaseService.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      if (response.user != null) {
        widget.onAuthChanged();
        if (!mounted) return;
        setState(() => _successMessage = '로그인되었습니다!');
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '인증 처리 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _codeSent = false;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  Future<void> _handleSignOut() async {
    setState(() => _isLoading = true);

    try {
      await SupabaseService.client.auth.signOut();
      // 로그아웃 후에도 게스트로 계속 사용할 수 있게 익명 세션 복구
      await SupabaseService.ensureGuestSession();
      widget.onAuthChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('성공적으로 로그아웃되었습니다.'),
            backgroundColor: Color(0xFF047857),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로그아웃 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF949494)),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF777777)),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(const Color(0xFFDFDFDF)),
      enabledBorder: border(const Color(0xFFDFDFDF)),
      focusedBorder: border(const Color(0xFF047857), 1.5),
    );
  }

  Widget _primaryButton({required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF047857),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _messages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
        if (_successMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              _successMessage!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF047857), fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이메일 주소',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: _inputDecoration(hint: 'name@example.com', icon: Icons.email_outlined),
            onFieldSubmitted: (_) => _isLoading ? null : _sendCode(),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return '이메일을 입력해 주세요.';
              if (!val.contains('@')) return '올바른 이메일 형식을 입력해 주세요.';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _messages(),
          _primaryButton(label: '인증 코드 받기', onPressed: _sendCode),
          const SizedBox(height: 8),
          const Text(
            '비밀번호는 필요 없습니다. 이메일로 받은 코드만 입력하면 로그인/가입됩니다.',
            style: TextStyle(fontSize: 11, color: Color(0xFF777777)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '인증 코드',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 10,
            decoration: _inputDecoration(hint: '이메일로 받은 코드', icon: Icons.pin_outlined)
                .copyWith(counterText: ''),
            onFieldSubmitted: (_) => _isLoading ? null : _verifyCode(),
            validator: (val) {
              final v = val?.trim() ?? '';
              if (v.isEmpty) return '인증 코드를 입력해 주세요.';
              if (v.length < 6) return '인증 코드는 6자리 이상입니다.';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _messages(),
          _primaryButton(label: '로그인하기', onPressed: _verifyCode),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _isLoading ? null : _changeEmail,
                child: const Text('이메일 변경', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: (_isLoading || _cooldown > 0) ? null : _sendCode,
                child: Text(
                  _cooldown > 0 ? '코드 다시 받기 (${_cooldown}s)' : '코드 다시 받기',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildProfile(User user) {
    // 표시용 판별만 한다. user_metadata 는 사용자가 임의로 설정할 수 있어 신뢰하지 않는다.
    final isAdmin = user.email?.toLowerCase().trim() == 'bugye6816@gmail.com' ||
        user.appMetadata['role'] == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDFDFDF)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isAdmin ? const Color(0xFF047857) : const Color(0xFF3B82F6),
                child: Icon(
                  isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.email ?? '회원',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? const Color(0xFF047857).withValues(alpha: 0.15)
                                : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isAdmin ? '관리자' : '일반 회원',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isAdmin ? const Color(0xFF047857) : const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Supabase 데이터베이스 실시간 계정 연동 완료',
                      style: TextStyle(fontSize: 11, color: Color(0xFF777777)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleSignOut,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8332E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('로그아웃', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGuestBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF047857).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _emailLoginEnabled
            ? '지금은 게스트로 이용 중입니다. 로그인하지 않아도 지도 보기와 제보를 모두 사용할 수 있어요.'
            : '로그인 없이 게스트로 지도 보기와 제보를 모두 사용할 수 있어요. 이메일 로그인은 준비 중입니다.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF065F46)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final signedIn = user != null && !user.isAnonymous;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_rounded, color: Color(0xFF047857), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      signedIn ? '계정 및 프로필' : 'FlatWay 로그인',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF777777)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFEFEFEF)),
            if (signedIn)
              _buildProfile(user)
            else ...[
              _buildGuestBanner(),
              if (_emailLoginEnabled) _codeSent ? _buildCodeStep() : _buildEmailStep(),
              if (!_emailLoginEnabled) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
