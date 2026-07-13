import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/settings_page_chrome.dart';

/// Standard page shell: centered transparent AppBar + consistent body padding.
///
/// Use for settings / tools / secondary routes so chrome matches theme defaults.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.leading,
    this.padding = kSettingsPagePadding,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? leading;
  final EdgeInsetsGeometry padding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        title: Text(title),
        leading: leading,
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

/// Scrollable settings body with shared padding.
class AppSettingsScrollBody extends StatelessWidget {
  const AppSettingsScrollBody({
    required this.children,
    this.physics,
    this.controller,
    this.padding = kSettingsPagePadding,
    super.key,
  });

  final List<Widget> children;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: physics,
      padding: padding,
      children: children,
    );
  }
}
