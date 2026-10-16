import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messapp/providers.dart';
import 'package:messapp/services/collection_cloud_service.dart';
import 'package:messapp/services/mess_cloud_service.dart';
import 'package:messapp/ui/collection_screen.dart';

void main() {
  Future<void> openCollections(
    WidgetTester tester,
    Future<Map<String, MemberCollection>> Function(String month) load,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMessProvider.overrideWith(
            (ref) async => Mess(
              id: 'test-mess',
              name: 'Test mess',
              ownerUid: 'owner',
              joinCode: 'test-code',
              myRole: 'member',
            ),
          ),
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 10)),
          sharedCollectionsProvider.overrideWith((ref, month) => load(month)),
        ],
        child: const MaterialApp(home: CollectionScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, MemberCollection> collections(
    String month,
    List<double> shares,
  ) => {
    for (var i = 0; i < shares.length; i++)
      'member$i@example.com': MemberCollection(
        email: 'member$i@example.com',
        month: month,
        amountDue: shares[i],
      ),
  };

  testWidgets('saved uniform shares appear without editing on this device', (
    tester,
  ) async {
    await openCollections(
      tester,
      (month) async => collections(month, [5000, 5000]),
    );
    expect(find.text('not set'), findsNothing);
    expect(find.text('PKR 5,000'), findsOneWidget);
  });

  testWidgets('mixed member shares are not reported as unset', (tester) async {
    await openCollections(
      tester,
      (month) async => collections(month, [5000, 0]),
    );
    expect(find.text('varies by member'), findsOneWidget);
    expect(find.text('not set'), findsNothing);
  });

  testWidgets(
    'month navigation reads that month instead of retaining a share',
    (tester) async {
      await openCollections(
        tester,
        (month) async => collections(month, [month == '2026-10' ? 5000 : 0]),
      );
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('not set'), findsOneWidget);
      expect(find.text('PKR 5,000'), findsNothing);
    },
  );

  testWidgets(
    'refresh reloads shared collections and updates displayed shares',
    (tester) async {
      var reads = 0;
      await openCollections(tester, (month) async {
        reads++;
        return collections(month, [reads == 1 ? 5000 : 6000]);
      });
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('PKR 6,000'), findsNWidgets(3));
      expect(find.text('PKR 5,000'), findsNothing);
    },
  );
}
