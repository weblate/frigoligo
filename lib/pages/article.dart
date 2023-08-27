import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:fwfh_cached_network_image/fwfh_cached_network_image.dart';
import 'package:fwfh_url_launcher/fwfh_url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/article.dart';
import '../providers/article.dart';
import '../providers/expander.dart';
import '../widgets/async_action_button.dart';

class ArticlePage extends StatefulWidget {
  // TODO articleId is not used but required to avoid triggering flutter caching
  // maybe that's just a setState() missing somewhere
  const ArticlePage({super.key, required this.articleId, this.drawer});

  final int articleId;
  final Widget? drawer;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  bool _stateChangePending = false;
  bool _starredChangePending = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final article = provider.article;
    final scroller = ScrollController();

    final toggler = context.watch<Expander?>();
    Widget? leading;
    if (toggler != null) {
      leading = IconButton(
        icon: Icon(
            toggler.expanded ? Icons.list : Icons.keyboard_double_arrow_left),
        onPressed: toggler.toggle,
      );
    }

    late final Widget bodyBuilder;
    if (article == null) {
      bodyBuilder = _buildNoArticle();
    } else if (article.content == null) {
      bodyBuilder = _buildEmptyContent(Uri.parse(article.url));
    } else {
      bodyBuilder = _buildArticleContent(article, provider, scroller);
    }

    return SelectionArea(
      child: Scaffold(
        appBar: AppBar(
          leading: leading,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (article != null)
              AsyncActionButton(
                icon: stateIcons[article.stateValue]!,
                progressValue: _stateChangePending ? 0 : null,
                onPressed: () => provider.modifyAndRefresh(
                  archive: article.archivedAt == null,
                  onProgress: (progress) =>
                      setState(() => _stateChangePending = progress < 1),
                ),
              ),
            if (article != null)
              AsyncActionButton(
                icon: starredIcons[article.starredValue]!,
                progressValue: _starredChangePending ? 0 : null,
                onPressed: () => provider.modifyAndRefresh(
                  starred: article.starredAt == null,
                  onProgress: (progress) =>
                      setState(() => _starredChangePending = progress < 1),
                ),
              ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  enabled: article != null,
                  child: ListTile(
                    leading: shareIcon,
                    title: const Text('Share'),
                  ),
                ),
                PopupMenuItem(
                  value: 'open',
                  enabled: article != null,
                  child: const ListTile(
                    leading: Icon(Icons.open_in_browser),
                    title: Text('Open in browser'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: article != null,
                  child: const ListTile(
                    leading: Icon(Icons.delete),
                    title: Text('Delete article'),
                  ),
                ),
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'share':
                    final box = context.findRenderObject() as RenderBox?;
                    Share.share(
                      article!.url,
                      subject: article.title,
                      sharePositionOrigin:
                          box!.localToGlobal(Offset.zero) & box.size,
                    );
                  case 'open':
                    launchUrl(Uri.parse(article!.url));
                  case 'delete':
                    final result = await showOkCancelAlertDialog(
                      context: context,
                      title: 'Delete this article',
                      message: article!.title,
                      okLabel: 'Delete',
                      isDestructiveAction: true,
                    );
                    if (result == OkCancelResult.cancel) return;
                    await provider.delete();
                    if (toggler == null && context.mounted) {
                      context.go('/');
                    }
                }
              },
            ),
          ],
        ),
        body: bodyBuilder,
        drawer: widget.drawer,
      ),
    );
  }

  Widget _buildNoArticle() {
    return const Center(child: Icon(Icons.question_mark));
  }

  Widget _buildEmptyContent(Uri articleUrl) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No content fetched',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8.0),
          ElevatedButton(
            onPressed: () => launchUrl(articleUrl),
            child: const Text('Browse the original'),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleContent(
      Article article, ArticleProvider provider, scroller) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            !provider.isPositionRestorePending) {
          provider.saveScrollPosition(notification.metrics.pixels);
        }
        return false;
      },
      child: Scrollbar(
        controller: scroller,
        child: SingleChildScrollView(
          key: GlobalObjectKey('articlepage-${provider.articleId}'),
          controller: scroller,
          child: Column(
            children: [
              _buildHeader(article),
              const Divider(),
              _buildContent(article.content!, scroller, provider)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Article article) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Text(
            article.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(article.domainName ?? article.url),
              const Text(' - '),
              const Icon(Icons.timer_outlined),
              Text('${article.readingTime} min'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      String content, ScrollController scroller, ArticleProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: HtmlWidget(
        content,
        factoryBuilder: () => HtmlWidgetFactory(
          onTreeBuilt: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
            if (provider.isPositionRestorePending) {
              scroller.jumpTo(provider.scrollPosition!);
              provider.hasJumpedToPosition = true;
            }
          }),
        ),
      ),
    );
  }
}

class HtmlWidgetFactory extends WidgetFactory
    with CachedNetworkImageFactory, UrlLauncherFactory {
  HtmlWidgetFactory({this.onTreeBuilt});

  void Function(Widget)? onTreeBuilt;

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    final body = super.buildBodyWidget(context, child);
    onTreeBuilt?.call(body);
    return body;
  }
}
