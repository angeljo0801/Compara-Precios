import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const PriceApp());

class PriceApp extends StatelessWidget {
  const PriceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Compara Precios',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3157d5)), useMaterial3: true),
    home: const HomePage(),
  );
}

class Store {
  final String name, url;
  const Store(this.name, this.url);
  Map<String, String> toJson() => {'name': name, 'url': url};
  factory Store.fromJson(Map<String, dynamic> j) => Store(j['name'] ?? '', j['url'] ?? '');
}

class Offer {
  final String title, store, link, image;
  final double price;
  const Offer({required this.title, required this.store, required this.link, required this.price, this.image = ''});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final query = TextEditingController();
  final zip = TextEditingController();
  final apiKey = TextEditingController();
  bool loading = false;
  String? error;
  List<Offer> offers = [];
  List<Store> customStores = [];

  static const stores = [
    Store('Amazon', 'https://www.amazon.com/s?k='), Store('Walmart', 'https://www.walmart.com/search?q='),
    Store('Target', 'https://www.target.com/s?searchTerm='), Store('Best Buy', 'https://www.bestbuy.com/site/searchpage.jsp?st='),
    Store('eBay', 'https://www.ebay.com/sch/i.html?_nkw='), Store('Home Depot', 'https://www.homedepot.com/s/'),
    Store("Lowe's", 'https://www.lowes.com/search?searchTerm='), Store('Costco', 'https://www.costco.com/CatalogSearch?keyword='),
    Store('Walgreens', 'https://www.walgreens.com/search/results.jsp?Ntt='), Store('CVS', 'https://www.cvs.com/search?searchTerm='),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    apiKey.text = p.getString('apiKey') ?? '';
    zip.text = p.getString('zip') ?? '';
    final raw = p.getStringList('stores') ?? [];
    if (mounted) setState(() => customStores = raw.map((e) => Store.fromJson(jsonDecode(e))).toList());
  }

  Future<void> search() async {
    if (query.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { loading = true; error = null; offers = []; });
    if (apiKey.text.trim().isEmpty) {
      setState(() { loading = false; error = 'Añade tu clave de SerpApi en Configuración para recibir precios comparados.'; });
      return;
    }
    try {
      final params = {'engine':'google_shopping','q':query.text.trim(),'gl':'us','hl':'es','api_key':apiKey.text.trim()};
      if (zip.text.trim().isNotEmpty) params['location'] = zip.text.trim();
      final uri = Uri.https('serpapi.com', '/search.json', params);
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw Exception('Servicio respondió ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['shopping_results'] as List? ?? []);
      final parsed = items.map((x) {
        final m = x as Map<String, dynamic>;
        final raw = (m['extracted_price'] as num?)?.toDouble() ?? 0;
        return Offer(title:m['title'] ?? 'Producto', store:m['source'] ?? 'Tienda', link:m['product_link'] ?? m['link'] ?? '', price:raw, image:m['thumbnail'] ?? '');
      }).where((o) => o.price > 0).toList()..sort((a,b) => a.price.compareTo(b.price));
      setState(() { offers = parsed; if (parsed.isEmpty) error = 'No se encontraron precios para esta búsqueda.'; });
    } catch (e) {
      setState(() => error = 'No se pudo consultar: $e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> openStore(Store s) async {
    final uri = Uri.parse('${s.url}${Uri.encodeComponent(query.text.trim())}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> settings() async {
    final key = TextEditingController(text: apiKey.text), z = TextEditingController(text: zip.text);
    await showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Configuración'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller:key, obscureText:true, decoration:const InputDecoration(labelText:'Clave de SerpApi', helperText:'Se guarda solo en este teléfono')),
      const SizedBox(height:12), TextField(controller:z, keyboardType:TextInputType.number, decoration:const InputDecoration(labelText:'Código postal', helperText:'Ayuda a encontrar comercios locales')),
    ])), actions:[TextButton(onPressed:()=>Navigator.pop(c), child:const Text('Cancelar')), FilledButton(onPressed:() async {
      apiKey.text=key.text.trim(); zip.text=z.text.trim(); final p=await SharedPreferences.getInstance(); await p.setString('apiKey',apiKey.text); await p.setString('zip',zip.text); if(c.mounted) Navigator.pop(c);
    }, child:const Text('Guardar'))]));
  }

  Future<void> addStore() async {
    final name=TextEditingController(), url=TextEditingController();
    await showDialog(context: context, builder:(c)=>AlertDialog(title:const Text('Añadir tienda'), content:Column(mainAxisSize:MainAxisSize.min, children:[
      TextField(controller:name, decoration:const InputDecoration(labelText:'Nombre de la tienda')),
      TextField(controller:url, keyboardType:TextInputType.url, decoration:const InputDecoration(labelText:'URL de búsqueda', hintText:'https://tienda.com/search?q=')),
    ]), actions:[TextButton(onPressed:()=>Navigator.pop(c), child:const Text('Cancelar')), FilledButton(onPressed:() async {
      if(name.text.trim().isEmpty || !url.text.trim().startsWith('http')) return;
      setState(()=>customStores.add(Store(name.text.trim(),url.text.trim()))); final p=await SharedPreferences.getInstance(); await p.setStringList('stores',customStores.map((e)=>jsonEncode(e.toJson())).toList()); if(c.mounted) Navigator.pop(c);
    }, child:const Text('Añadir'))]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Compara Precios'), actions:[IconButton(onPressed:settings, icon:const Icon(Icons.settings_outlined))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:addStore, icon:const Icon(Icons.add_business), label:const Text('Añadir tienda')),
    body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.all(16), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[
        const Text('Encuentra el mejor precio', style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
        const SizedBox(height:12), TextField(controller:query, onSubmitted:(_)=>search(), decoration:InputDecoration(prefixIcon:const Icon(Icons.search), hintText:'Producto, marca o modelo', suffixIcon:IconButton(icon:const Icon(Icons.arrow_forward),onPressed:search), border:const OutlineInputBorder())),
        const SizedBox(height:10), SizedBox(height:42, child:ListView(scrollDirection:Axis.horizontal, children:[...stores,...customStores].map((s)=>Padding(padding:const EdgeInsets.only(right:8), child:ActionChip(avatar:const Icon(Icons.storefront,size:18),label:Text(s.name),onPressed:()=>openStore(s)))).toList())),
      ])),
      if(loading) const LinearProgressIndicator(),
      if(error!=null) Padding(padding:const EdgeInsets.all(20),child:Text(error!,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      Expanded(child:offers.isEmpty && !loading && error==null ? const _Empty() : ListView.builder(padding:const EdgeInsets.fromLTRB(12,0,12,90),itemCount:offers.length,itemBuilder:(c,i){final o=offers[i];return Card(child:ListTile(
        leading:o.image.isEmpty?const CircleAvatar(child:Icon(Icons.shopping_bag)):ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.network(o.image,width:58,height:58,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.shopping_bag))),
        title:Text(o.title,maxLines:2,overflow:TextOverflow.ellipsis), subtitle:Text(o.store), trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('\$${o.price.toStringAsFixed(2)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),const Text('Ver oferta',style:TextStyle(fontSize:11))]),
        onTap:o.link.isEmpty?null:()=>launchUrl(Uri.parse(o.link),mode:LaunchMode.externalApplication),
      ));})),
    ])),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context)=>const Center(child:Padding(padding:EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.manage_search,size:82,color:Color(0xff3157d5)),SizedBox(height:12),Text('Busca un producto para comparar tiendas online y comercios cercanos.',textAlign:TextAlign.center,style:TextStyle(fontSize:17))])));
}
