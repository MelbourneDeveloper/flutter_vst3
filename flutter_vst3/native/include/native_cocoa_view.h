// Copyright (c) 2025
// Native Cocoa/AppKit view fallback for macOS VST3 plugins

#pragma once

#import <Cocoa/Cocoa.h>
#include "public.sdk/source/vst/vsteditcontroller.h"
#include <string>

#define CONCAT_INNER(a, b) a##_##b
#define CONCAT(a, b) CONCAT_INNER(a, b)
#ifdef PLUGIN_TARGET_NAME
#define Vst3FlippedView CONCAT(Vst3FlippedView, PLUGIN_TARGET_NAME)
#define Vst3PluginEditorDelegate CONCAT(Vst3PluginEditorDelegate, PLUGIN_TARGET_NAME)
#endif

/// Delegate handling Cocoa sliders and parameter labels.
@interface Vst3PluginEditorDelegate : NSObject
@property (nonatomic, assign) Steinberg::Vst::EditController* controller;
@property (nonatomic, strong) NSMutableArray<NSSlider*>* sliders;
@property (nonatomic, strong) NSMutableArray<NSTextField*>* valueLabels;

- (void)onSliderChanged:(NSSlider*)sender;
- (void)updateParamId:(Steinberg::Vst::ParamID)paramId withValue:(Steinberg::Vst::ParamValue)value;
@end

/// Builds the native Cocoa fallback UI with header, sliders, and footer.
NSView* createCocoaFallbackView(
    NSView* parent,
    Steinberg::Vst::EditController* controller,
    const std::string& pluginName,
    Vst3PluginEditorDelegate** outDelegate);
