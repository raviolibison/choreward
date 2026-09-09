import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'billing_service.dart';

const _forest = Color(0xFF2D6A4F);

// Shows RevenueCat's current Offering for [householdId] and lets a parent
// buy Premium for that household. Purchasing does not set `isPremium`
// itself — that only ever happens server-side, via the revenueCatWebhook
// Cloud Function reacting to a confirmed purchase. See billing_service.dart.
class PaywallScreen extends StatefulWidget {
  final String householdId;
  const PaywallScreen({super.key, required this.householdId});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!isBillingSupported) {
      setState(() {
        _isLoading = false;
        _error = 'Upgrading to Premium is only available on the mobile app right now.';
      });
      return;
    }
    try {
      await BillingService.configureForHousehold(widget.householdId);
      final offerings = await BillingService.getOfferings();
      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load Premium plans: $e';
      });
    }
  }

  Future<void> _buy(Package package) async {
    setState(() {
      _isPurchasing = true;
      _error = null;
    });
    try {
      final completed = await BillingService.purchasePackage(package);
      if (!mounted) return;
      if (completed) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase complete! Premium unlocks within a few seconds.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Purchase failed: $e');
    }
    if (mounted) setState(() => _isPurchasing = false);
  }

  @override
  Widget build(BuildContext context) {
    final packages = _offerings?.current?.availablePackages ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Choreward Premium')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Premium unlocks:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Unlimited family members\n'
                  '• Assign chores to specific children\n'
                  '• Repeating chores\n'
                  '• More features coming soon',
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                ],
                if (packages.isNotEmpty)
                  ...packages.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ElevatedButton(
                        onPressed: _isPurchasing ? null : () => _buy(p),
                        style: ElevatedButton.styleFrom(backgroundColor: _forest),
                        child: Text(
                          '${p.storeProduct.title} — ${p.storeProduct.priceString}',
                        ),
                      ),
                    ),
                  )
                else if (_error == null)
                  const Text(
                    'No Premium plans are configured yet. Set up products in '
                    'App Store Connect / Play Console and an Offering in the '
                    'RevenueCat dashboard to enable purchasing here.',
                    style: TextStyle(color: Colors.grey),
                  ),
                if (_isPurchasing) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
    );
  }
}
