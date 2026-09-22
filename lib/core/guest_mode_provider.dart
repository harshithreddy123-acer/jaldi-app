import 'package:flutter_riverpod/flutter_riverpod.dart';

class GuestModeNotifier extends StateNotifier<bool> {
  GuestModeNotifier() : super(false);

  void setGuest(bool value) {
    state = value;
  }
}

final guestModeProvider = StateNotifierProvider<GuestModeNotifier, bool>((ref) {
  return GuestModeNotifier();
});
