#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

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
    '{{PLUGIN_NAME}}': metadata['pluginName'],
    '{{PLUGIN_NAME_UPPER}}': pluginName.toUpperCase(),
    '{{PLUGIN_NAME_CAMEL}}': pluginClass,
    '{{PLUGIN_CLASS_NAME}}': pluginClass,
    '{{PLUGIN_ID}}': pluginName,
    '{{COMPANY_NAME}}': metadata['vendor'],
    '{{PLUGIN_URL}}': metadata['companyWeb'],
    '{{PLUGIN_EMAIL}}': metadata['companyEmail'],
    '{{PLUGIN_CATEGORY}}': metadata['category'],
    '{{PLUGIN_VERSION}}': metadata['version'],
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
    return '        parameters.addParameter(STR16("$title"), STR16("${p['units']}"), 0, ${p['defaultValue']}, ParameterInfo::kCanAutomate, ${p['id']});';
  }).join('\n');
  
  // Generate parameter info getter
  final paramInfoCases = parameters.map((p) {
    final title = (p['name'] as String).replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join(' ');
    return '''        case ${p['id']}:
            info.id = ${p['id']};
            info.title = STR16("$title");
            info.shortTitle = STR16("$title");
            info.units = STR16("${p['units']}");
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

// Parameter IDs for ${metadata['pluginName']}
enum ${pluginClass}Parameters {
${parameters.map((p) => '    k${_toPascalCase(p['name'] as String)}Param = ${p['id']},').join('\n')}
    kNumParameters = ${parameters.length}
};

// Derived from the bundle identifier, so they are stable and unique per plugin.
static const FUID k${pluginClass}ProcessorUID(${pluginUid('${metadata['bundleIdentifier']}:processor')});
static const FUID k${pluginClass}ControllerUID(${pluginUid('${metadata['bundleIdentifier']}:controller')});
''';
  
  File('${genDir.path}/${targetName}_ids.h').writeAsStringSync(content);
  print('Generated: ${targetName}_ids.h');
}

void _generateCMakeMetadata(Directory genDir, Map<String, dynamic> metadata, List<Map<String, dynamic>> parameters) {
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

String _toPascalCase(String input) {
  return input.split('_').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join('');
}