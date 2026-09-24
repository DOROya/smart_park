import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

class DriverInAppCheckoutPage extends StatefulWidget {
  const DriverInAppCheckoutPage({
    super.key,
    required this.establishmentName,
    required this.checkoutUrl,
    this.checkPaid,
  });

  final String establishmentName;
  final String checkoutUrl;

  /// Asks the server whether this checkout has been paid. Without it the
  /// page can only detect payment from PayMongo's success redirect.
  final Future<bool> Function()? checkPaid;

  @override
  State<DriverInAppCheckoutPage> createState() =>
      _DriverInAppCheckoutPageState();
}

class _DriverInAppCheckoutPageState extends State<DriverInAppCheckoutPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _checkingStatus = false;
  bool _pollInFlight = false;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _checkSuccessUrl(url);
            if (mounted) {
              setState(() {
                _loading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            _checkSuccessUrl(url);
            _keepCheckoutNavigationInApp();
            if (mounted) {
              setState(() {
                _loading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_checkSuccessUrl(request.url)) {
              return NavigationDecision.prevent;
            }

            final Uri? uri = Uri.tryParse(request.url);
            final bool isWebNavigation =
                uri?.scheme == 'https' || uri?.scheme == 'http';
            if (isWebNavigation) {
              return NavigationDecision.navigate;
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This payment step must remain in SmartPark.'),
                ),
              );
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _loading = false;
                _errorMessage = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));

    _startBackgroundPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startBackgroundPolling() {
    if (widget.checkPaid == null) {
      return;
    }

    // Check right away in case the session already settled before this
    // page's first timer tick (e.g. a fast test-mode authorization).
    unawaited(_checkPaymentStatus(silent: true));

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkPaymentStatus(silent: true);
    });
  }

  bool _checkSuccessUrl(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('payment-success') ||
        lower.contains('paymongo.com/success')) {
      _pollTimer?.cancel();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return true;
    }
    if (lower.contains('payment-cancel') ||
        lower.contains('paymongo.com/cancel')) {
      _pollTimer?.cancel();
      if (mounted) {
        Navigator.of(context).pop(false);
      }
      return true;
    }
    return false;
  }

  Future<bool> _checkPaymentStatus({bool silent = false}) async {
    final Future<bool> Function()? checkPaid = widget.checkPaid;

    if (checkPaid == null) {
      if (!silent && mounted) {
        Navigator.of(context).pop(null);
      }
      return false;
    }

    // Guards against overlapping requests from both the manual button and
    // the periodic background timer — previously this only blocked manual
    // taps (the flag was set behind `!silent`), so a slow API response could
    // leave several silent polls in flight at once, and one of the earlier,
    // now-stale responses could be the one observed.
    if (_pollInFlight) return false;
    _pollInFlight = true;

    if (!silent && mounted) {
      setState(() {
        _checkingStatus = true;
      });
    }

    try {
      if (await checkPaid()) {
        _pollTimer?.cancel();
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return true;
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment is still being processed or pending. Please finish on screen or try again.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('PayMongo checkout status poll failed: $e');
    } finally {
      _pollInFlight = false;
      if (!silent && mounted) {
        setState(() {
          _checkingStatus = false;
        });
      }
    }
    return false;
  }

  Future<void> _keepCheckoutNavigationInApp() async {
    await _controller.runJavaScript('''
      (function() {
        window.open = function(url) {
          if (url) {
            window.location.assign(url);
          }
          return window;
        };
        document.addEventListener('click', function(event) {
          var link = event.target.closest('a[target="_blank"]');
          if (link && link.href) {
            event.preventDefault();
            window.location.assign(link.href);
          }
        }, true);
      })();
    ''');
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Secure Payment',
              style: TextStyle(
                color: AppTheme.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.establishmentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload checkout',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(color: AppTheme.accent),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 40,
                            color: Color(0xFF9A5A27),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Unable to load secure checkout.',
                            style: TextStyle(
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E5EC))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checkingStatus
                      ? null
                      : () => _checkPaymentStatus(),
                  icon: _checkingStatus
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.verified_outlined),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: const Color(0xFF22252C),
                    minimumSize: const Size.fromHeight(48),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  label: Text(
                    _checkingStatus
                        ? 'Checking status...'
                        : 'I Have Completed Payment',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
