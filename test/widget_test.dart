import 'package:flutter_test/flutter_test.dart';
import 'package:jaldi_app/main.dart';

void main() {
  testWidgets('shows setup instructions when backend is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const ConfigurationRequiredApp());
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
