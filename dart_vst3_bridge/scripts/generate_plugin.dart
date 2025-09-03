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
    ('plugin_processor_native.cpp.template', '${targetName}_processor_native.cpp')
  ];
  
  for (final template in templates) {
    final templateFile = File('$templateDir/${template.$1}');
    final outputFile = File('${genDir.path}/${template.$2}');
    
    if (!templateFile.existsSync()) {
      print('WARNING: Template missing: ${templateFile.path}');
      continue;
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
      '{{PARAMETER_VARIABLES}}': '    // No parameters',
      '{{PARAMETER_DEFAULTS}}': '    // No parameters to initialize',
      '{{PARAMETER_CONTROLLER_INIT}}': '    // No parameters to add',
      '{{PARAMETER_STATE_SAVE}}': '    // No parameters to save', 
      '{{PARAMETER_STATE_LOAD}}': '    // No parameters to load',
      '{{GET_PARAMETER_INFO}}': '        return kResultFalse;',
      '{{NORMALIZE_PARAMETER}}': '        return normalizedValue;',
      '{{DENORMALIZE_PARAMETER}}': '        return plainValue;',
      '{{STRING_TO_PARAMETER}}': '        return false;',
      '{{PARAMETER_TO_STRING}}': '        return false;',
    };
  }
  
  // Generate parameter variables
  final paramVars = parameters.map((p) => '    double ${p['name']} = ${p['defaultValue']};').join('\n');
  
  // Generate parameter initialization
  final paramDefaults = parameters.map((p) => '    ${p['name']} = ${p['defaultValue']};').join('\n');
  
  // Generate controller parameter registration
  final controllerInit = parameters.map((p) {
    final title = (p['name'] as String).replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join(' ');
    return '    parameters.addParameter(STR16("$title"), STR16("${p['units']}"), 0, ${p['defaultValue']}, ParameterInfo::kCanAutomate, ${p['id']});';
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
  
  // Generate state read/write
  final stateRead = parameters.map((p) => '''    // Read ${p['name']}
    if (state->read(&${p['name']}, sizeof(${p['name']}), &bytesRead) != kResultTrue) return kResultFalse;''').join('\n');
  
  final stateWrite = parameters.map((p) => '''    // Write ${p['name']}
    if (state->write(&${p['name']}, sizeof(${p['name']}), &bytesWritten) != kResultTrue) return kResultFalse;''').join('\n');
  
  return {
    '{{PARAMETER_COUNT}}': parameters.length.toString(),
    '{{PARAMETER_VARIABLES}}': paramVars,
    '{{PARAMETER_DEFAULTS}}': paramDefaults,
    '{{PARAMETER_CONTROLLER_INIT}}': controllerInit,
    '{{GET_PARAMETER_INFO}}': paramInfoCases + '\n        return kResultFalse;',
    '{{NORMALIZE_PARAMETER}}': '        return normalizedValue; // Identity for now',
    '{{DENORMALIZE_PARAMETER}}': '        return plainValue; // Identity for now',
    '{{STRING_TO_PARAMETER}}': '        return false; // Not implemented',
    '{{PARAMETER_TO_STRING}}': '        return false; // Not implemented',
    '{{PARAMETER_STATE_READ}}': parameters.isEmpty ? '        // No parameters to read' : '    int32 bytesRead = 0;\n$stateRead',
    '{{PARAMETER_STATE_WRITE}}': parameters.isEmpty ? '        // No parameters to write' : '    int32 bytesWritten = 0;\n$stateWrite',
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

// Plugin UIDs as proper FUID objects (generate proper GUIDs in production)
static const FUID k${pluginClass}ProcessorUID(0xF9D0C991, 0x074C8404, 0x4D825FC5, 0x21E8F92B);
static const FUID k${pluginClass}ControllerUID(0xA0115732, 0x16F06596, 0x4B9846B6, 0x007933D0);
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
''';
  
  File('${genDir.path}/metadata.cmake').writeAsStringSync(content);
}

String _toPascalCase(String input) {
  return input.split('_').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)).join('');
}