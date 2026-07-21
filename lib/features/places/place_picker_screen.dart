import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import '../../widgets/skeleton.dart';

/// Signature of the nearby-candidate fetch function. Matches
/// [PlacesRepository.fetchNearbyCandidates] exactly so tests can inject a
/// synchronous stub without modifying production call sites.
typedef NearbyFetcher = Future<List<PlaceCandidate>> Function({
  required double lat,
  required double lng,
  List<MerchantCandidate> candidates,
  String? merchantName,
  String? category,
  int limit,
});

/// Signature of the text-search fetch used by the in-sheet search mode.
/// Matches [PlacesRepository.search].
typedef PlaceSearchFetcher = Future<List<PlaceResult>> Function(
  String query, {
  double? lat,
  double? lng,
});

/// Full-screen location picker (design handoff Screen 2,
/// `docs/design/design_handoff_receipt_flows/`): full-bleed map with the
/// capture-location radius ring and candidate pins, plus a pull-up sheet of
/// nearby place candidates ranked by the same text+distance scoring the
/// enrichment pipeline uses. A search mode inside the sheet falls back to
/// Google Places text search.
///
/// Opened via [push], which bypasses go_router so it works from inside a
/// modal bottom sheet (AdaptiveSheet / showModalBottomSheet).
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.candidates,
    this.merchantName,
    this.category,
    @visibleForTesting this.candidatesFetcher,
    @visibleForTesting this.searchFetcher,
    @visibleForTesting this.mapOverride,
  });

  final double lat;
  final double lng;
  final List<MerchantCandidate> candidates;
  final String? merchantName;
  final String? category;

  /// Override the fetch implementation in widget tests to avoid network calls.
  @visibleForTesting
  final NearbyFetcher? candidatesFetcher;

  /// Override the search implementation in widget tests to avoid network calls.
  @visibleForTesting
  final PlaceSearchFetcher? searchFetcher;

  /// Overrides the real `GoogleMap` in widget tests, which can't construct a
  /// live platform view outside a real device/emulator.
  @visibleForTesting
  final Widget? mapOverride;

  static Future<PlaceResult?> push(
    BuildContext context, {
    required double lat,
    required double lng,
    List<MerchantCandidate> candidates = const [],
    String? merchantName,
    String? category,
  }) {
    return Navigator.of(context, rootNavigator: true).push<PlaceResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlacePickerScreen(
          lat: lat,
          lng: lng,
          candidates: candidates,
          merchantName: merchantName,
          category: category,
        ),
      ),
    );
  }

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen>
    with TickerProviderStateMixin {
  /// Mirrors SEARCH_RADIUS_METERS in supabase/functions/_shared/place_matching.ts
  /// so the ring shows the area the backend actually searched.
  static const _searchRadiusMeters = 300.0;

  GoogleMapController? _controller;

  /// Sheet entrance: slides up from off-screen whenever the screen is pushed.
  late final AnimationController _sheetController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();
  late final Animation<Offset> _sheetSlide = Tween<Offset>(
    begin: const Offset(0, 1.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _sheetController,
    curve: const Cubic(0.22, 0.9, 0.32, 1),
  ));

  List<PlaceCandidate> _results = const [];
  bool _loading = true;
  int? _selectedIndex;

  bool _searchOpen = false;
  bool _searching = false;
  List<PlaceResult> _searchResults = const [];
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _fetchCandidates();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _fetchCandidates() async {
    final fetch =
        widget.candidatesFetcher ?? PlacesRepository.fetchNearbyCandidates;
    final results = await fetch(
      lat: widget.lat,
      lng: widget.lng,
      candidates: widget.candidates,
      merchantName: widget.merchantName,
      category: widget.category,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      if (results.isNotEmpty) _selectedIndex = 0;
    });
    if (results.isNotEmpty) {
      // Move the camera to the top candidate once the map has been built —
      // deferred a frame since the map's `onMapCreated` may not have fired
      // yet (see `_focusOnTopCandidateIfReady`).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusOnTopCandidateIfReady();
      });
    }
  }

  /// `GoogleMapController` only exists once the platform view finishes
  /// creating, which can race with [_fetchCandidates] resolving — this is
  /// called from both `onMapCreated` and the post-frame callback above, and
  /// no-ops until both the controller and results are ready.
  void _focusOnTopCandidateIfReady() {
    final controller = _controller;
    if (controller == null || _results.isEmpty) return;
    final c = _results[0];
    controller.moveCamera(
      CameraUpdate.newLatLngZoom(LatLng(c.lat, c.lng), 17),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _focusOnTopCandidateIfReady();
  }

  void _selectCandidate(int index) {
    setState(() => _selectedIndex = index);
    final c = _results[index];
    _animatedMapMove(LatLng(c.lat, c.lng), 17);
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchOpen = false;
      _searching = false;
      _searchResults = const [];
      _searchController.clear();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final fetch = widget.searchFetcher ?? PlacesRepository.search;
      final results = await fetch(query, lat: widget.lat, lng: widget.lng);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  /// Promotes a text-search result to the top of the candidate list and
  /// selects it, so Confirm commits it like any nearby candidate.
  void _pickSearchResult(PlaceResult result) {
    final distance = Geolocator.distanceBetween(
      widget.lat,
      widget.lng,
      result.lat,
      result.lng,
    );
    final candidate = PlaceCandidate(
      id: result.id,
      name: result.name,
      address: result.address,
      lat: result.lat,
      lng: result.lng,
      distanceMeters: distance,
      confidence: 1,
    );
    _searchDebounce?.cancel();
    setState(() {
      _results = [
        candidate,
        ..._results.where((c) => c.id != candidate.id),
      ];
      _selectedIndex = 0;
      _searchOpen = false;
      _searching = false;
      _searchResults = const [];
      _searchController.clear();
    });
    _animatedMapMove(LatLng(candidate.lat, candidate.lng), 17);
  }

  void _animatedMapMove(LatLng dest, double destZoom) {
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(dest, destZoom),
      duration: const Duration(milliseconds: 550),
    );
  }

  void _confirm() {
    final i = _selectedIndex;
    if (i == null || i >= _results.length) return;
    Navigator.of(context).pop(_results[i].toPlaceResult());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReceiptSheetColors.surface,
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          _buildTopBar(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: _sheetSlide,
              child: _buildSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (widget.mapOverride != null) return widget.mapOverride!;

    final here = LatLng(widget.lat, widget.lng);
    final selected = _selectedIndex;
    // GoogleMap renders full-bleed behind the pull-up sheet (up to 60% of
    // screen height, see _buildSheet) and the top search bar — without
    // `padding`, the SDK centers markers/camera targets on the *whole*
    // widget, which puts them right under the sheet, out of view. `padding`
    // tells the SDK how much of the widget is actually occluded so it
    // re-centers within the remaining visible strip instead.
    final mapPadding = EdgeInsets.only(
      top: 90 + MediaQuery.paddingOf(context).top,
      bottom: MediaQuery.sizeOf(context).height * 0.6,
    );
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: here, zoom: 16),
      onMapCreated: _onMapCreated,
      onTap: (_) {},
      padding: mapPadding,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      circles: {
        Circle(
          circleId: const CircleId('search-radius'),
          center: here,
          radius: _searchRadiusMeters,
          fillColor: ReceiptSheetColors.gold.withValues(alpha: 0.12),
          strokeColor: ReceiptSheetColors.linkStrong.withValues(alpha: 0.35),
          strokeWidth: 2,
        ),
        Circle(
          circleId: const CircleId('you-are-here'),
          center: here,
          radius: 6,
          fillColor: ReceiptSheetColors.youAreHere,
          strokeColor: Colors.white,
          strokeWidth: 3,
        ),
      },
      markers: {
        for (var i = 0; i < _results.length; i++)
          Marker(
            markerId: MarkerId(_results[i].id),
            position: LatLng(_results[i].lat, _results[i].lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              i == selected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
            ),
            onTap: () => _selectCandidate(i),
          ),
      },
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(
          children: [
            _CircleIconButton(
              size: 42,
              background: Colors.white,
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).pop(null),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _openSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: ReceiptSheetColors.sheetShadow,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: ReceiptSheetColors.youAreHere,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Which restaurant was this?',
                        style: balooText(
                          14,
                          FontWeight.w600,
                          color: ReceiptSheetColors.sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: ReceiptSheetColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kReceiptSheetRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: ReceiptSheetColors.sheetShadow,
            blurRadius: 40,
            offset: Offset(0, -18),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + safeBottom + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ReceiptSheetHandle(),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: _sheetBody())),
          if (!_loading && _results.isNotEmpty) ...[
            const SizedBox(height: 18),
            ReceiptSheetCta(
              label: 'Confirm location',
              onPressed: _selectedIndex != null ? _confirm : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sheetBody() {
    if (_loading) return const _CandidateListSkeleton();
    if (_searchOpen) return _searchBody();
    if (_results.isEmpty) return _emptyBody();
    return _browseBody();
  }

  Widget _browseBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the location',
          style: balooText(
            18,
            FontWeight.w800,
            color: ReceiptSheetColors.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_results.length} spot${_results.length == 1 ? '' : 's'} '
          'found nearby',
          style: balooText(13, FontWeight.w600, color: ReceiptSheetColors.sub),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _results.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _CandidateRow(
            candidate: _results[i],
            selected: i == _selectedIndex,
            onTap: () => _selectCandidate(i),
          ),
        ],
      ],
    );
  }

  Widget _searchBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _CircleIconButton(
              size: 34,
              background: ReceiptSheetColors.tile,
              icon: Icons.arrow_back,
              onTap: _closeSearch,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: ReceiptSheetColors.tile,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 16,
                      color: ReceiptSheetColors.sub,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: _onSearchChanged,
                        cursorColor: ReceiptSheetColors.gold,
                        style: balooText(
                          14,
                          FontWeight.w600,
                          color: ReceiptSheetColors.ink,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Search for a restaurant or address',
                          hintStyle: balooText(
                            14,
                            FontWeight.w600,
                            color: ReceiptSheetColors.subLight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_searching) ...[
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ReceiptSheetColors.gold,
              ),
            ),
          ),
        ] else if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final result in _searchResults.take(4)) ...[
            _SearchResultRow(
              result: result,
              onTap: () => _pickSearchResult(result),
            ),
            const SizedBox(height: 10),
          ],
        ] else if (_searchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'No matches — try a different name',
              style: balooText(
                13,
                FontWeight.w600,
                color: ReceiptSheetColors.sub,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptyBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const Icon(
          Icons.location_off_outlined,
          size: 42,
          color: ReceiptSheetColors.subLight,
        ),
        const SizedBox(height: 12),
        Text(
          'No nearby places found',
          style: balooText(15, FontWeight.w800, color: ReceiptSheetColors.ink),
        ),
        const SizedBox(height: 8),
        ReceiptSheetLink(
          label: 'Search by name instead',
          color: ReceiptSheetColors.link,
          onTap: _openSearch,
        ),
      ],
    );
  }
}

/// Skeleton placeholder shown in the sheet while candidates are loading,
/// shaped like [_browseBody]'s header + [_CandidateRow]s so the real content
/// doesn't visually "pop in" once it arrives.
class _CandidateListSkeleton extends StatelessWidget {
  const _CandidateListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Skeleton(
      palette: SkeletonPalette.receiptSheet,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 150, height: 20),
          SizedBox(height: 8),
          SkeletonBox(width: 120, height: 13),
          SizedBox(height: 14),
          _SkeletonCandidateRow(),
          SizedBox(height: 10),
          _SkeletonCandidateRow(),
          SizedBox(height: 10),
          _SkeletonCandidateRow(),
        ],
      ),
    );
  }
}

class _SkeletonCandidateRow extends StatelessWidget {
  const _SkeletonCandidateRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ReceiptSheetColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReceiptSheetColors.rowBorder, width: 2),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 38, height: 38, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.size,
    required this.background,
    required this.icon,
    required this.onTap,
  });

  final double size;
  final Color background;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: background == Colors.white ? 4 : 0,
      shadowColor: ReceiptSheetColors.sheetShadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 17, color: ReceiptSheetColors.body),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final PlaceCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  String get _distanceLabel {
    final meters = candidate.distanceMeters;
    return meters < 1000
        ? '${meters.round()}m'
        : '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? ReceiptSheetColors.selectedTint
              : ReceiptSheetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? ReceiptSheetColors.gold
                : ReceiptSheetColors.rowBorder,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? ReceiptSheetColors.gold
                    : ReceiptSheetColors.tile,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.location_on_outlined,
                size: 18,
                color: selected
                    ? ReceiptSheetColors.ctaText
                    : ReceiptSheetColors.sub,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: balooText(
                      15,
                      FontWeight.w800,
                      color: ReceiptSheetColors.ink,
                    ),
                  ),
                  if (candidate.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      candidate.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: balooText(
                        12.5,
                        FontWeight.w600,
                        color: ReceiptSheetColors.sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _distanceLabel,
                  style: balooText(
                    12,
                    FontWeight.w700,
                    color: selected
                        ? ReceiptSheetColors.distanceSelected
                        : ReceiptSheetColors.subLight,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? ReceiptSheetColors.gold : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? ReceiptSheetColors.gold
                          : ReceiptSheetColors.checkboxBorder,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.result, required this.onTap});

  final PlaceResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ReceiptSheetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ReceiptSheetColors.rowBorder, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ReceiptSheetColors.tile,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: ReceiptSheetColors.sub,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: balooText(
                      15,
                      FontWeight.w800,
                      color: ReceiptSheetColors.ink,
                    ),
                  ),
                  if (result.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: balooText(
                        12.5,
                        FontWeight.w600,
                        color: ReceiptSheetColors.sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
