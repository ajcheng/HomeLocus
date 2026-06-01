import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检索')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SearchBar(
              hintText: '输入物品名称、品牌、或描述...',
              onSubmitted: (value) {},
              leading: const Icon(Icons.search),
              trailing: [
                IconButton(icon: const Icon(Icons.image), onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
