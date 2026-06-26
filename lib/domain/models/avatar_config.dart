import 'package:flutter/material.dart';

/// Avatar body/fill color options.
enum AvatarColorOption {
  yellow,
  coral,
  lime,
  blue,
  purple,
  pink,
  brown,
  gray,
  white,
}

extension AvatarColorOptionX on AvatarColorOption {
  /// Swatch hex values ported from Impact Drops' avatar customizer.
  Color get swatch {
    switch (this) {
      case AvatarColorOption.yellow:
        return const Color(0xFFFFCC29);
      case AvatarColorOption.coral:
        return const Color(0xFFFF6655);
      case AvatarColorOption.lime:
        return const Color(0xFF9CD650);
      case AvatarColorOption.blue:
        return const Color(0xFF6FB8E8);
      case AvatarColorOption.purple:
        return const Color(0xFFC7A8E8);
      case AvatarColorOption.pink:
        return const Color(0xFFF5B5C5);
      case AvatarColorOption.brown:
        return const Color(0xFFB89B7A);
      case AvatarColorOption.gray:
        return const Color(0xFFBFBFBF);
      case AvatarColorOption.white:
        return const Color(0xFFF2EFE9);
    }
  }

  String get label {
    switch (this) {
      case AvatarColorOption.yellow:
        return 'Yellow';
      case AvatarColorOption.coral:
        return 'Coral';
      case AvatarColorOption.lime:
        return 'Lime';
      case AvatarColorOption.blue:
        return 'Blue';
      case AvatarColorOption.purple:
        return 'Purple';
      case AvatarColorOption.pink:
        return 'Pink';
      case AvatarColorOption.brown:
        return 'Brown';
      case AvatarColorOption.gray:
        return 'Gray';
      case AvatarColorOption.white:
        return 'White';
    }
  }
}

/// Avatar eye styles. `neutral` is the avatar customizer's "default" option
/// (renamed since `default` is a reserved word in Dart).
enum AvatarEyesOption {
  neutral,
  dot,
  happy,
  wink,
  squint,
  sleepy,
  blink,
  star,
  heart,
  glasses,
}

extension AvatarEyesOptionX on AvatarEyesOption {
  String get label {
    switch (this) {
      case AvatarEyesOption.neutral:
        return 'Default';
      case AvatarEyesOption.dot:
        return 'Dot';
      case AvatarEyesOption.happy:
        return 'Happy';
      case AvatarEyesOption.wink:
        return 'Wink';
      case AvatarEyesOption.squint:
        return 'Squint';
      case AvatarEyesOption.sleepy:
        return 'Sleepy';
      case AvatarEyesOption.blink:
        return 'Blink';
      case AvatarEyesOption.star:
        return 'Star';
      case AvatarEyesOption.heart:
        return 'Heart';
      case AvatarEyesOption.glasses:
        return 'Glasses';
    }
  }
}

/// Avatar hat overlays.
enum AvatarHatOption {
  none,
  cap,
  beanie,
  crown,
  party,
  headband,
  catEars,
  plant,
  propeller,
  tophat,
}

extension AvatarHatOptionX on AvatarHatOption {
  String get label {
    switch (this) {
      case AvatarHatOption.none:
        return 'None';
      case AvatarHatOption.cap:
        return 'Cap';
      case AvatarHatOption.beanie:
        return 'Beanie';
      case AvatarHatOption.crown:
        return 'Crown';
      case AvatarHatOption.party:
        return 'Party';
      case AvatarHatOption.headband:
        return 'Headband';
      case AvatarHatOption.catEars:
        return 'Cat Ears';
      case AvatarHatOption.plant:
        return 'Plant';
      case AvatarHatOption.propeller:
        return 'Prop';
      case AvatarHatOption.tophat:
        return 'Top Hat';
    }
  }
}

/// User-customizable avatar appearance (color/eyes/hat), persisted to
/// `profiles.avatar_config` and synced across devices.
class AvatarConfig {
  const AvatarConfig({
    required this.color,
    required this.eyes,
    required this.hat,
  });

  final AvatarColorOption color;
  final AvatarEyesOption eyes;
  final AvatarHatOption hat;

  factory AvatarConfig.defaultConfig() => const AvatarConfig(
        color: AvatarColorOption.yellow,
        eyes: AvatarEyesOption.neutral,
        hat: AvatarHatOption.cap,
      );

  AvatarConfig copyWith({
    AvatarColorOption? color,
    AvatarEyesOption? eyes,
    AvatarHatOption? hat,
  }) {
    return AvatarConfig(
      color: color ?? this.color,
      eyes: eyes ?? this.eyes,
      hat: hat ?? this.hat,
    );
  }

  Map<String, dynamic> toJson() => {
        'color': color.name,
        'eyes': eyes.name,
        'hat': hat.name,
      };

  factory AvatarConfig.fromJson(Map<String, dynamic> json) {
    final defaults = AvatarConfig.defaultConfig();
    return AvatarConfig(
      color: _enumFromName(AvatarColorOption.values, json['color']) ??
          defaults.color,
      eyes: _enumFromName(AvatarEyesOption.values, json['eyes']) ??
          defaults.eyes,
      hat: _enumFromName(AvatarHatOption.values, json['hat']) ?? defaults.hat,
    );
  }
}

T? _enumFromName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
