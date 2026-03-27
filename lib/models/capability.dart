import 'package:flutter/material.dart';

class Capability {
  final String section;
  final String name;
  final String description;
  final List<String> tags;
  bool isEnabled;

  Capability({
    required this.section,
    required this.name,
    required this.description,
    required this.tags,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'section': section,
    'name': name,
    'description': description,
    'tags': tags,
    'isEnabled': isEnabled,
  };

  factory Capability.fromJson(Map<String, dynamic> json) => Capability(
    section: json['section'],
    name: json['name'],
    description: json['description'],
    tags: json['tags'],
    isEnabled: json['isEnabled'] ?? true,
  );
}

class CapabilitySection {
  final String title;
  final String icon;
  final Color color;
  final Color bg;
  final List<Capability> items;

  CapabilitySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.bg,
    required this.items,
  });
}
