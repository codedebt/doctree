import 'package:doctree_frontend/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Doctree app starts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DoctreeApp()),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
