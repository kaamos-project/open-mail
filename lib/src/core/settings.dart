/// What to do with remote images in HTML mail.
enum RemoteImages {
  /// Block them and offer "Carica immagini" (the default: privacy).
  ask,

  /// Always load them. The sender learns when and where you read.
  always,
}

/// How the desktop shows the list and the open message.
enum MailLayout {
  /// List and reader side by side.
  split,

  /// Only the list; an open message takes the whole area, like classic
  /// Gmail. "Indietro" goes back to the list.
  list,
}

/// Where a new message is written on desktop.
enum ComposeMode {
  /// A floating window at the bottom right, like Gmail.
  window,

  /// A page over the list and the reader, with "Indietro".
  page,
}

/// The app's settings. Saved on the device only (`settings.json`).
///
/// Only the phone ignores [layout] and [compose]: there the list and the
/// message are always pages.
class AppSettings {
  /// Creates settings; the defaults are the app's behaviour without a file.
  const AppSettings({
    this.remoteImages = RemoteImages.ask,
    this.layout = MailLayout.split,
    this.compose = ComposeMode.window,
  });

  /// Reads the saved JSON. Unknown or missing values fall back to the
  /// default: an older or newer file never stops the app.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return AppSettings(
      remoteImages: pick(
        RemoteImages.values,
        json['remoteImages'],
        RemoteImages.ask,
      ),
      layout: pick(MailLayout.values, json['layout'], MailLayout.split),
      compose: pick(ComposeMode.values, json['compose'], ComposeMode.window),
    );
  }

  /// Remote images in HTML mail.
  final RemoteImages remoteImages;

  /// The desktop layout.
  final MailLayout layout;

  /// Where to write on desktop.
  final ComposeMode compose;

  /// A copy with some values changed.
  AppSettings copyWith({
    RemoteImages? remoteImages,
    MailLayout? layout,
    ComposeMode? compose,
  }) => AppSettings(
    remoteImages: remoteImages ?? this.remoteImages,
    layout: layout ?? this.layout,
    compose: compose ?? this.compose,
  );

  /// The JSON to save. Enum names, not indexes: reordering an enum must not
  /// change a saved choice.
  Map<String, Object?> toJson() => {
    'version': 1,
    'remoteImages': remoteImages.name,
    'layout': layout.name,
    'compose': compose.name,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.remoteImages == remoteImages &&
      other.layout == layout &&
      other.compose == compose;

  @override
  int get hashCode => Object.hash(remoteImages, layout, compose);
}
