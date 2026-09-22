import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { customer, provider, admin, unknown }

class UserRoleNotifier extends StateNotifier<UserRole> {
  UserRoleNotifier() : super(UserRole.unknown) {
    _fetchRole();
  }

  Future<void> _fetchRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        state = UserRole.unknown;
        return;
      }

      final data = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null && data['role'] != null) {
        final roleString = data['role'] as String;
        state = UserRole.values.firstWhere(
          (r) => r.name == roleString,
          orElse: () => UserRole.customer,
        );
      } else {
        state = UserRole.customer; // Default role
      }
    } catch (e) {
      state = UserRole.unknown;
    }
  }

  Future<void> refreshRole() async {
    await _fetchRole();
  }
}

final userRoleProvider = StateNotifierProvider<UserRoleNotifier, UserRole>((ref) {
  return UserRoleNotifier();
});
