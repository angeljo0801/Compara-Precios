# Compara Precios

Aplicación Flutter para Android que compara productos mediante Google Shopping (SerpApi), ordena las ofertas de menor a mayor y permite abrir búsquedas directas en tiendas conocidas o añadidas por el usuario.

## Incluye

- Amazon, Walmart, Target, Best Buy, eBay, Home Depot, Lowe's, Costco, Walgreens y CVS.
- Resultados online y locales según código postal.
- Alta ilimitada de tiendas mediante nombre y URL de búsqueda.
- Precio, tienda, imagen, enlace y orden de menor a mayor.
- La clave de consulta se guarda únicamente en el dispositivo.

## Compilar

1. Instala Flutter estable.
2. Ejecuta `flutter create . --platforms android` dentro de esta carpeta.
3. Ejecuta `flutter pub get`.
4. Ejecuta `flutter build apk --release`.
5. El APK quedará en `build/app/outputs/flutter-apk/app-release.apk`.

Para precios reales, crea una clave en SerpApi y añádela desde Configuración. Las cuotas y condiciones dependen de ese proveedor. Las tiendas agregadas manualmente funcionan como accesos directos; para integrar sus resultados en la lista, la tienda debe ofrecer una API o un conector compatible.
