// Smoke tests for app startup routing: auth state -> Login / Setup / role screen.
import 'package:chore_app/login_screen.dart';
import 'package:chore_app/main.dart';
import 'package:chore_app/setup_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() async {
    // Screens construct services that touch Firebase singletons, so a
    // (mocked) default app must exist even though the tests inject fakes.
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    // Don't hit the network for fonts; fall back to the default font.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('signed-out user sees the login screen', (tester) async {
    await tester.pumpWidget(MyApp(
      auth: MockFirebaseAuth(),
      firestore: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('signed-in user without a household sees setup', (tester) async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'parent@example.com'),
    );
    await tester.pumpWidget(MyApp(
      auth: auth,
      firestore: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
