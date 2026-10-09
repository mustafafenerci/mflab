import 'dart:convert';

import 'package:flutter/services.dart';

class PackageLink {
  PackageLink(this.name, this.url);
  final String name;
  final String url;
}

class PackageAction {
  PackageAction(this.json);
  final Map<String, dynamic> json;
  String get label => json['label'] as String;
  String get service => json['service'] as String;
  String? get prompt => json['prompt'] as String?;
  String get command => json['command'] as String;
  String? get afterInfo => json['afterInfo'] as String?;
}

class LabPackage {
  LabPackage(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get type => json['type'] as String;
  String get why => json['why'] as String;
  String get info => (json['info'] ?? '') as String;
  List<String> get steps => List<String>.from(json['steps'] as List);
  String? get check => json['check'] as String?;
  String? get downloadUrl => json['downloadUrl'] as String?;
  String? get compose => json['compose'] as String?;
  String? get buildContext => json['buildContext'] as String?;
  List<int> get ports => List<int>.from((json['ports'] ?? const []) as List);
  bool get isDocker => type == 'docker';

  List<PackageLink> get links => ((json['links'] ?? const []) as List)
      .map((l) => PackageLink(l['name'] as String, l['url'] as String))
      .toList();

  List<PackageAction> get actions => ((json['actions'] ?? const []) as List)
      .map((a) => PackageAction(a as Map<String, dynamic>))
      .toList();
}

class Course {
  Course(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get description => json['description'] as String;
  String get icon => (json['icon'] ?? 'school') as String;
  String get workspaceName => (json['workspaceName'] ?? 'calisma') as String;
  List<String> get packages => List<String>.from(json['packages'] as List);
  List<String> get extensions =>
      List<String>.from((json['extensions'] ?? const []) as List);
}

class HelpEntry {
  HelpEntry(this.json);
  final Map<String, dynamic> json;
  List<String> get match => List<String>.from(json['match'] as List);
  String get title => json['title'] as String;
  String get explain => json['explain'] as String;
  String get url => json['url'] as String;
}

class Catalog {
  Catalog(this.packages, this.courses, this.help);
  final Map<String, LabPackage> packages;
  final List<Course> courses;
  final List<HelpEntry> help;

  static Future<Catalog> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final pkgs = <String, LabPackage>{};
    for (final path in manifest.listAssets()) {
      if (path.startsWith('assets/packages/') && path.endsWith('.json')) {
        final p = LabPackage(
            jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>);
        pkgs[p.id] = p;
      }
    }
    final courses = (jsonDecode(
            await rootBundle.loadString('assets/courses/courses.json')) as List)
        .map((c) => Course(c as Map<String, dynamic>))
        .toList();
    final help = (jsonDecode(
            await rootBundle.loadString('assets/help/errors.json')) as List)
        .map((h) => HelpEntry(h as Map<String, dynamic>))
        .toList();
    return Catalog(pkgs, courses, help);
  }
}

class UpdateInfo {
  UpdateInfo(this.version, this.url, this.notes, this.mandatory);
  final String version;
  final String url;
  final String notes;
  final bool mandatory;
}
