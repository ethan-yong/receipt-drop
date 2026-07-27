/// Resolved source for displaying a receipt photo on detail/viewer screens.
///
/// Prefer [localPath] when the on-device file still exists (fully offline).
/// Fall back to a short-lived signed [imageUrl] when only Storage has it.
/// [unavailable] covers the rare case where neither is reachable.
class ReceiptDisplayImage {
  const ReceiptDisplayImage.local(this.localPath)
      : imageUrl = null,
        source = ReceiptDisplayImageSource.local;

  const ReceiptDisplayImage.remote(this.imageUrl)
      : localPath = null,
        source = ReceiptDisplayImageSource.remote;

  const ReceiptDisplayImage.unavailable()
      : localPath = null,
        imageUrl = null,
        source = ReceiptDisplayImageSource.unavailable;

  final ReceiptDisplayImageSource source;
  final String? localPath;
  final String? imageUrl;

  bool get isAvailable => source != ReceiptDisplayImageSource.unavailable;
}

enum ReceiptDisplayImageSource { local, remote, unavailable }
