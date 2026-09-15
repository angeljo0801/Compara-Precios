import 'package:flutter_test/flutter_test.dart';
import 'package:compara_precios/main.dart';

void main() {
  testWidgets('muestra búsqueda principal', (tester) async {
    await tester.pumpWidget(const PriceApp());
    expect(find.text('Compara Precios'), findsOneWidget);
    expect(find.text('Encuentra el mejor precio'), findsOneWidget);
  });
}
