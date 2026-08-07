import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/bill_split_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/avatar_config.dart';
import '../../domain/models/bill_split.dart';
import '../../widgets/blob_avatar.dart';
import '../../widgets/skeleton.dart';

/// A friend's view of every split they're a participant in — the only
/// discovery surface for a Bill Split request, since this app has no
/// push-notification system (see `BillSplitRepository.sendReminder`'s doc
/// comment). Reachable from the Home screen's pending-requests banner.
///
/// Minimal UI, matching `FriendsScreen`'s own "minimal for v1" precedent:
/// each row's status pill is directly tappable to self-report paid, rather
/// than opening a separate detail screen for the same single action.
class SplitRequestsScreen extends StatefulWidget {
  const SplitRequestsScreen({super.key});

  @override
  State<SplitRequestsScreen> createState() => _SplitRequestsScreenState();
}

class _SplitRequestsScreenState extends State<SplitRequestsScreen> {
  List<MySplitRequestView>? _requests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requests = await BillSplitRepository.getMySplitRequests();
    if (mounted) setState(() => _requests = requests);
  }

  Future<void> _togglePaid(MySplitRequestView r) async {
    final next = !r.paid;
    setState(() {
      _requests = [
        for (final req in _requests!)
          if (req.participantId == r.participantId)
            MySplitRequestView(
              splitId: req.splitId,
              participantId: req.participantId,
              transactionId: req.transactionId,
              merchantRaw: req.merchantRaw,
              payerUserId: req.payerUserId,
              payerDisplayName: req.payerDisplayName,
              payerAvatarConfigJson: req.payerAvatarConfigJson,
              mode: req.mode,
              totalMyr: req.totalMyr,
              shareMyr: req.shareMyr,
              paid: next,
              paidAt: next ? DateTime.now() : null,
              createdAt: req.createdAt,
            )
          else
            req,
      ];
    });
    await BillSplitRepository.setParticipantPaid(r.participantId, next);
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Split requests'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: requests == null
            ? const _SplitRequestsSkeleton()
            : requests.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Text(
                          "No one's split a bill with you yet.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      for (final r in requests) _SplitRequestTile(request: r, onToggle: () => _togglePaid(r)),
                    ],
                  ),
      ),
    );
  }
}

class _SplitRequestsSkeleton extends StatelessWidget {
  const _SplitRequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                SkeletonCircle(size: 40),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: SkeletonBox(width: double.infinity, height: 14)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitRequestTile extends StatelessWidget {
  const _SplitRequestTile({required this.request, required this.onToggle});

  final MySplitRequestView request;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final config = request.payerAvatarConfigJson != null
        ? AvatarConfig.fromJson(request.payerAvatarConfigJson!)
        : AvatarConfig.defaultConfig();
    final merchant = request.merchantRaw?.trim();
    final paid = request.paid;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          BlobAvatar(mood: AvatarMood.balanced, config: config, size: 40, animate: false),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.payerDisplayName ?? 'A friend'}'
                  '${merchant != null && merchant.isNotEmpty ? ' · $merchant' : ''}',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'You owe RM ${request.shareMyr.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: paid ? BillSplitColors.paidBg : AppColors.badgePendingBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                paid ? 'Paid ✓' : "I've paid",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: paid ? BillSplitColors.paidText : AppColors.badgePendingText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
