import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class CoinLogo extends StatelessWidget {
  const CoinLogo({super.key, required this.coin, this.size = 46});

  final String coin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = coin.toUpperCase();
    final config = switch (normalized) {
      'BTC' => (
        color: const Color(0xffffa726),
        label: '₿',
        url: 'https://assets.coingecko.com/coins/images/1/large/bitcoin.png',
      ),
      'ETH' => (
        color: const Color(0xff7c8cff),
        label: '◆',
        url: 'https://assets.coingecko.com/coins/images/279/large/ethereum.png',
      ),
      'USDC' => (
        color: const Color(0xff2775ca),
        label: r'$',
        url: 'https://assets.coingecko.com/coins/images/6319/large/usdc.png',
      ),
      'USDT' => (
        color: const Color(0xff26a17b),
        label: '₮',
        url: 'https://assets.coingecko.com/coins/images/325/large/Tether.png',
      ),
      _ => (
        color: AppTheme.primary,
        label: normalized.characters.first,
        url: '',
      ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: config.color,
        boxShadow: [
          BoxShadow(
            color: config.color.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: config.url.isEmpty
            ? _FallbackLogo(label: config.label, size: size)
            : ClipOval(
                child: Image.network(
                  config.url,
                  width: size * 0.76,
                  height: size * 0.76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _FallbackLogo(label: config.label, size: size),
                ),
              ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.48,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
