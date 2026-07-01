import 'package:file_picker/file_picker.dart';

import 'package:flutter/cupertino.dart';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';



import '../../core/platform/adaptive_sheet.dart';

import '../../core/platform/platform_utils.dart';



enum ReceiptCaptureAction {

  camera,

  gallery,

  file,

  shareHint,

}



/// Platform-native menu: Cupertino action sheet on iOS, Material sheet on Android.

class ReceiptCaptureMenu {

  ReceiptCaptureMenu._();



  static Future<void> show(

    BuildContext context, {

    required VoidCallback onCamera,

    required VoidCallback onGallery,

    required VoidCallback onFile,

    required VoidCallback onShareHint,

  }) async {

    final showCamera =

        !kIsWeb &&

        (defaultTargetPlatform == TargetPlatform.android ||

            defaultTargetPlatform == TargetPlatform.iOS);



    final actions = <AdaptiveAction<ReceiptCaptureAction>>[

      if (showCamera)

        AdaptiveAction(

          label: 'Take photo',

          icon: PlatformUtils.isCupertino

              ? CupertinoIcons.camera

              : Icons.photo_camera_outlined,

          value: ReceiptCaptureAction.camera,

        ),

      if (showCamera)

        AdaptiveAction(

          label: 'Choose from gallery',

          icon: PlatformUtils.isCupertino

              ? CupertinoIcons.photo

              : Icons.photo_library_outlined,

          value: ReceiptCaptureAction.gallery,

        ),

      AdaptiveAction(

        label: 'Choose file (image or PDF)',

        icon: PlatformUtils.isCupertino

            ? CupertinoIcons.doc

            : Icons.upload_file_outlined,

        value: ReceiptCaptureAction.file,

      ),

      AdaptiveAction(

        label: 'Share from another app',

        icon: PlatformUtils.isCupertino

            ? CupertinoIcons.share

            : Icons.share_outlined,

        value: ReceiptCaptureAction.shareHint,

      ),

    ];



    final choice = await AdaptiveSheet.showActions<ReceiptCaptureAction>(

      context: context,

      title: 'Add a receipt',

      actions: actions,

    );



    switch (choice) {

      case ReceiptCaptureAction.camera:

        onCamera();

      case ReceiptCaptureAction.gallery:

        onGallery();

      case ReceiptCaptureAction.file:

        onFile();

      case ReceiptCaptureAction.shareHint:

        onShareHint();

      case null:

        break;

    }

  }



  static Future<({Uint8List bytes, String mimeType})?> pickDocumentFile() async {

    final result = await FilePicker.platform.pickFiles(

      type: FileType.custom,

      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf', 'heic', 'webp'],

      withData: true,

    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;

    final bytes = file.bytes;

    if (bytes == null) return null;

    final ext = (file.extension ?? 'jpg').toLowerCase();

    final mime = ext == 'pdf' ? 'application/pdf' : 'image/$ext';

    return (bytes: bytes, mimeType: mime);

  }

}

