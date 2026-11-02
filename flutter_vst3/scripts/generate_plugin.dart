#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

/// Generates native plugin sources from the command-line metadata directory.
void main(List<String> args) {
  if (args.length < 3 || args.length > 4) {
    print('USAGE: generate_plugin.dart <plugin_dir> <plugin_name> <target_name> [build_dir]');
    exit(1);
  }

  final pluginDir = args[0];
  final pluginName = args[1]; 
  final targetName = args[2];
  final buildDir = args.length == 4 ? args[3] : null;

  try {
    generatePluginFiles(pluginDir, pluginName, targetName, buildDir);
    print('SUCCESS: Generated VST3 plugin files');
  } catch (e) {
    print('CRITICAL ERROR: $e');
    exit(1);
  }
}

/// Writes native sources and CMake metadata, rejecting unsupported metadata.
void generatePluginFiles(String pluginDir, String pluginName, String targetName, String? buildDir) {
  // Read metadata JSON  
  final metadataFile = File('$pluginDir/plugin_metadata.json');
  if (!metadataFile.existsSync()) {
    throw Exception('${metadataFile.path} not found!');
  }

  final metadata = jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
  
  // Validate required fields
  final required = ['pluginName', 'vendor', 'version', 'category', 'bundleIdentifier', 'companyWeb', 'companyEmail'];
  for (final field in required) {
    if (!metadata.containsKey(field)) {
      throw Exception('Required field "$field" missing from plugin_metadata.json');
    }
  }

  final parameters = (metadata['parameters'] as List? ?? [])
      .cast<Map<String, dynamic>>();
  _validateParameterIds(parameters);
  _validateNames(parameters);
  _validateTarget(targetName);
  _validateTarget(pluginName);
  _validateMetadata(metadata, parameters);
  _validateUids(metadata);

  // Generate files
  final genDir = buildDir != null 
      ? Directory('$buildDir/generated')
      : Directory('$pluginDir/generated');
  
  genDir.createSync(recursive: true);

  final pluginClass = _toPascalCase(targetName);
  
  // Find templates directory
  final scriptDir = Directory.fromUri(Platform.script).parent.path;
  final templateDir = '$scriptDir/../native/templates';
  
  // Generate C++ code snippets
  final cppSnippets = _generateCppSnippets(parameters, metadata, pluginName);
  
  // Base replacements
  final replacements = {
    '{{PLUGIN_NAME}}': _cpp(metadata['pluginName']),
    '{{PLUGIN_NAME_UPPER}}': pluginName.toUpperCase(),
    '{{PLUGIN_NAME_CAMEL}}': pluginClass,
    '{{PLUGIN_CLASS_NAME}}': pluginClass,
    '{{PLUGIN_ID}}': pluginName,
    '{{COMPANY_NAME}}': _cpp(metadata['vendor']),
    '{{PLUGIN_URL}}': _cpp(metadata['companyWeb']),
    '{{PLUGIN_EMAIL}}': _cpp(metadata['companyEmail']),
    '{{PLUGIN_CATEGORY}}': _cpp(metadata['category']),
    '{{PLUGIN_VERSION}}': _cpp(metadata['version']),
  };
  
  // Add generated C++ code
  replacements.addAll(cppSnippets);
  
  // Generate files from templates - using AOT template
  final templates = [
    ('plugin_controller.cpp.template', '${targetName}_controller.cpp'),
    ('plugin_processor_aot.cpp.template', '${targetName}_processor.cpp'),
    ('plugin_factory.cpp.template', '${targetName}_factory.cpp'),
  ];
  
  for (final template in templates) {
    final templateFile = File('$templateDir/${template.$1}');
    final outputFile = File('${genDir.path}/${template.$2}');
    
    if (!templateFile.existsSync()) {
      throw Exception('Template missing: ${templateFile.path}');
    }
    
    var content = templateFile.readAsStringSync();
    
    // Replace all placeholders
    for (final replacement in replacements.entries) {
      content = content.replaceAll(replacement.key, replacement.value);
    }
    
    // Check for unresolved placeholders
    if (content.contains('{{')) {
      final unresolved = RegExp(r'\{\{[^}]+\}\}').allMatches(content).map((m) => m.group(0)).toList();
      throw Exception('Unresolved placeholders in ${template.$2}: $unresolved');
    }
    
    outputFile.writeAsStringSync(content);
    print('Generated: ${template.$2}');
  }
  
  // Generate IDs header
  _generateIdsHeader(genDir, targetName, pluginClass, parameters, metadata);
  
  // Generate CMake metadata
  _generateCMakeMetadata(genDir, metadata, parameters);
  
  print('Generated ${parameters.length} parameter(s)');
}

Map<String, String> _generateCppSnippets(List<Map<String, dynamic>> parameters, Map<String, dynamic> metadata, String pluginName) {
  if (parameters.isEmpty) {
    return {
      '{{PARAMETER_COUNT}}': '0',
      '{{PARAMETER_DEFAULT_VALUES}}': '',
      '{{PARAMETER_CONTROLLER_INIT}}': '    // No parameters to add',
      '{{PARAMETER_STATE_SAVE}}': '    // No parameters to save', 
      '{{PARAMETER_STATE_LOAD}}': '    // No parameters to load',
      '{{GET_PARAMETER_INFO}}': '        return kResultFalse;',
      '{{NORMALIZE_PARAMETER}}': '        return normalizedValue;',
      '{{DENORMALIZE_PARAMETER}}': '        return plainValue;',
      '{{STRING_TO_PARAMETER}}': '        return EditController::getParamValueByString(id, string, valueNormalized);',
      '{{PARAMETER_TO_STRING}}': '        return EditController::getParamStringByValue(id, valueNormalized, string);',
    };
  }
  
  // Generate controller parameter registration
  final controllerInit = parameters.map((p) {
    final title = (p['name'] as String).replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join(' ');
    return '        parameters.addParameter(STR16("${_cpp(title)}"), STR16("${_cpp(p['units'])}"), 0, ${p['defaultValue']}, ParameterInfo::kCanAutomate, ${p['id']});';
  }).join('\n');
  
  // Generate parameter info getter
  final paramInfoCases = parameters.map((p) {
    final title = (p['name'] as String).replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join(' ');
    return '''        case ${p['id']}:
            info.id = ${p['id']};
            info.title = STR16("${_cpp(title)}");
            info.shortTitle = STR16("${_cpp(title)}");
            info.units = STR16("${_cpp(p['units'])}");
            info.stepCount = 0;
            info.defaultNormalizedValue = ${p['defaultValue']};
            info.flags = ParameterInfo::kCanAutomate;
            return kResultTrue;''';
  }).join('\n');
  
  return {
    '{{PARAMETER_COUNT}}': parameters.length.toString(),
    '{{PARAMETER_DEFAULT_VALUES}}': parameters.map((p) => '${p['defaultValue']}').join(', '),
    '{{PARAMETER_CONTROLLER_INIT}}': controllerInit,
    '{{GET_PARAMETER_INFO}}': paramInfoCases + '\n        return kResultFalse;',
    '{{NORMALIZE_PARAMETER}}': '        return normalizedValue; // Identity for now',
    '{{DENORMALIZE_PARAMETER}}': '        return plainValue; // Identity for now',
    '{{STRING_TO_PARAMETER}}': '        return EditController::getParamValueByString(id, string, valueNormalized);',
    '{{PARAMETER_TO_STRING}}': '        return EditController::getParamStringByValue(id, valueNormalized, string);',
  };
}

void _generateIdsHeader(Directory genDir, String targetName, String pluginClass, List<Map<String, dynamic>> parameters, Map<String, dynamic> metadata) {
  final content = '''#pragma once
#include "pluginterfaces/base/funknown.h"

using namespace Steinberg;

// Parameter IDs for ${_comment(metadata['pluginName'])}
enum ${pluginClass}Parameters {
${parameters.map((p) => '    k${_toPascalCase(p['name'] as String)}Param = ${p['id']},').join('\n')}
    kNumParameters = ${parameters.length}
};

// Pinned in plugin_metadata.json, or derived from the bundle identifier, so they
// are stable and unique per plugin.
static const FUID k${pluginClass}ProcessorUID(${_classUid(metadata, 'processor')});
static const FUID k${pluginClass}ControllerUID(${_classUid(metadata, 'controller')});
''';
  
  File('${genDir.path}/${targetName}_ids.h').writeAsStringSync(content);
  print('Generated: ${targetName}_ids.h');
}

void _generateCMakeMetadata(Directory genDir, Map<String, dynamic> metadata, List<Map<String, dynamic>> parameters) {
  metadata = metadata.map((key, value) => MapEntry(key, value is String ? _cmake(value) : value));
  final content = '''set(JSON_PLUGIN_NAME "${metadata['pluginName']}")
set(JSON_VENDOR "${metadata['vendor']}")
set(JSON_VERSION "${metadata['version']}")
set(JSON_CATEGORY "${metadata['category']}")
set(JSON_BUNDLE_ID "${metadata['bundleIdentifier']}")
set(JSON_WEB "${metadata['companyWeb']}")
set(JSON_EMAIL "${metadata['companyEmail']}")
set(PARAM_COUNT "${parameters.length}")
set(JSON_FLUTTER_ENTRYPOINT "${metadata['flutterEntrypoint'] ?? ''}")
''';
  
  File('${genDir.path}/metadata.cmake').writeAsStringSync(content);
}

/// Throws unless parameter ids are exactly 0..n-1. The processor, controller and
/// saved state formats all index parameters by id.
void _validateParameterIds(List<Map<String, dynamic>> parameters) {
  for (var i = 0; i < parameters.length; i++) {
    if (parameters[i]['id'] != i) {
      throw Exception('Parameter ids must be 0..n-1 in order. Index $i has id ${parameters[i]['id']}');
    }
  }
}

/// Returns four comma-separated 32-bit hex words derived from [key] with
/// FNV-1a, for use as a VST3 FUID. The same key always gives the same result.
String pluginUid(String key) {
  return List.generate(4, (word) {
    var hash = 0x811C9DC5 ^ word;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return '0x${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }).join(', ');
}

/// A plugin that shipped with a UID pins it in its metadata, because hosts find
/// a plugin in saved projects by UID. Any other plugin gets one from its bundle id.
String _classUid(Map<String, dynamic> metadata, String kind) => switch (metadata['${kind}Uid']) {
      null => pluginUid('${metadata['bundleIdentifier']}:$kind'),
      final String uid => [
          for (var word = 0; word < 4; word++)
            '0x${uid.substring(word * 8, word * 8 + 8).toUpperCase()}',
        ].join(', '),
      final other => throw FormatException('Metadata error: ${kind}Uid must be 32 hex digits: $other'),
    };

void _validateUids(Map<String, dynamic> metadata) {
  final processor = metadata['processorUid'];
  final controller = metadata['controllerUid'];
  (processor == null) == (controller == null)
      ? null : throw const FormatException('Metadata error: processorUid and controllerUid must be set together');
  processor != null && processor == controller
      ? throw const FormatException('Metadata error: processorUid and controllerUid must differ') : null;
  for (final kind in ['processor', 'controller']) {
    final uid = metadata['${kind}Uid'];
    uid == null || (uid is String && RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(uid))
        ? null : throw FormatException('Metadata error: ${kind}Uid must be 32 hex digits: $uid');
  }
}

String _toPascalCase(String input) => _identifier(input);

String _identifier(String input) {
  final words = input.split(RegExp(r'[^a-zA-Z0-9]+')).where((w) => w.isNotEmpty);
  final result = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
  return RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(result)
      ? result : throw FormatException('Metadata error: unusable identifier: $input');
}

void _validateNames(List<Map<String, dynamic>> parameters) {
  final seen = <String>{'NumParameters'};
  for (final parameter in parameters) {
    final name = _identifier(parameter['name'] as String);
    seen.add(name) ? null : throw FormatException('Metadata error: duplicate parameter identifier $name');
  }
}

void _validateTarget(String value) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)
        ? null : throw FormatException('Metadata error: invalid target: $value');

void _validateMetadata(Map<String, dynamic> metadata, List<Map<String, dynamic>> parameters) {
  for (final key in ['pluginName', 'vendor', 'version', 'category', 'bundleIdentifier', 'companyWeb', 'companyEmail']) {
    _validateText(metadata[key]);
  }
  for (final p in parameters) {
    p['id'] is int ? null : throw const FormatException('Metadata error: parameter id must be an integer');
    _validateText(p['name']);
    _validateText(p['units']);
    final value = p['defaultValue'];
    value is num && value.isFinite && value >= 0 && value <= 1
        ? null : throw FormatException('Metadata error: invalid parameter default: $value');
  }
}

void _validateText(dynamic value) => value is String && !value.contains(RegExp(r'[\x00-\x1f\x7f]'))
    ? null : throw const FormatException('Metadata error: expected text without control characters');

String _cpp(dynamic value) => value.toString().replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r');

String _comment(dynamic value) => _cpp(value).endsWith(r'\') ? '${_cpp(value)} ' : _cpp(value);

String _cmake(dynamic value) => _cpp(value).replaceAll(r'$', r'\$').replaceAll(';', r'\;');