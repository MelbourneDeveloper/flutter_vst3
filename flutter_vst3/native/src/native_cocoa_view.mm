// Copyright (c) 2025
// Native Cocoa/AppKit view fallback for macOS VST3 plugins

#import "native_cocoa_view.h"
#include "pluginterfaces/base/ustring.h"
#include <cmath>

@interface Vst3FlippedView : NSView
@end

@implementation Vst3FlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@implementation Vst3PluginEditorDelegate
- (void)onSliderChanged:(NSSlider*)sender {
    if (!_controller) return;
    auto pid = static_cast<Steinberg::Vst::ParamID>(sender.tag);
    double val = [sender doubleValue];
    _controller->beginEdit(pid);
    _controller->setParamNormalized(pid, val);
    _controller->performEdit(pid, val);
    _controller->endEdit(pid);
    [self refreshLabelForParam:pid value:val slider:sender];
}

- (void)refreshLabelForParam:(Steinberg::Vst::ParamID)pid value:(double)val slider:(NSSlider*)slider {
    Steinberg::Vst::String128 str;
    _controller->getParamStringByValue(pid, val, str);
    char ascii[128] = {0};
    Steinberg::UString128(str).toAscii(ascii, sizeof(ascii));
    NSString* text = (ascii[0] != '\0')
        ? [NSString stringWithUTF8String:ascii]
        : [NSString stringWithFormat:@"%.1f%%", val * 100.0];
    NSInteger idx = [_sliders indexOfObject:slider];
    if (idx != NSNotFound && idx < static_cast<NSInteger>(_valueLabels.count)) {
        [_valueLabels[idx] setStringValue:text];
    }
}

- (void)updateParamId:(Steinberg::Vst::ParamID)pid withValue:(Steinberg::Vst::ParamValue)value {
    for (NSUInteger i = 0; i < _sliders.count; ++i) {
        if (static_cast<Steinberg::Vst::ParamID>(_sliders[i].tag) == pid) {
            if (std::abs([_sliders[i] doubleValue] - value) > 1e-5) {
                [_sliders[i] setDoubleValue:value];
                if (_controller && i < _valueLabels.count) {
                    [self refreshLabelForParam:pid value:value slider:_sliders[i]];
                }
            }
            break;
        }
    }
}
@end

static void buildHeader(NSView* parent, const std::string& name) {
    CGFloat w = parent.bounds.size.width;
    NSView* header = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, 64)];
    header.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

    NSTextField* title = [NSTextField labelWithString:[NSString stringWithUTF8String:name.c_str()]];
    title.frame = NSMakeRect(24, 12, 300, 24);
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    title.textColor = [NSColor whiteColor];
    [header addSubview:title];

    NSTextField* sub = [NSTextField labelWithString:@"flutter_vst3 • Pure Dart DSP & UI"];
    sub.frame = NSMakeRect(24, 38, 300, 16);
    sub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    sub.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    [header addSubview:sub];

    NSBox* sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, 63, w, 1)];
    sep.boxType = NSBoxSeparator;
    sep.autoresizingMask = NSViewWidthSizable;
    [header addSubview:sep];
    [parent addSubview:header];
}

static void buildSingleRow(
    NSView* parent,
    Steinberg::Vst::EditController* controller,
    const Steinberg::Vst::ParameterInfo& info,
    CGFloat width,
    CGFloat y,
    Vst3PluginEditorDelegate* delegate) {
    char asciiTitle[128] = {0};
    Steinberg::UString128(info.title).toAscii(asciiTitle, sizeof(asciiTitle));
    NSString* name = (asciiTitle[0] != '\0')
        ? [NSString stringWithUTF8String:asciiTitle]
        : [NSString stringWithFormat:@"Param %d", info.id];

    NSTextField* nameLabel = [NSTextField labelWithString:name];
    nameLabel.frame = NSMakeRect(24, y, width - 160, 18);
    nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    nameLabel.textColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    [parent addSubview:nameLabel];

    double val = controller->getParamNormalized(info.id);
    NSTextField* valLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%.1f%%", val * 100.0]];
    valLabel.frame = NSMakeRect(width - 134, y, 110, 18);
    valLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    valLabel.textColor = [NSColor colorWithCalibratedRed:0.25 green:0.75 blue:1.0 alpha:1.0];
    valLabel.alignment = NSTextAlignmentRight;
    valLabel.autoresizingMask = NSViewMinXMargin;
    [parent addSubview:valLabel];
    [delegate.valueLabels addObject:valLabel];

    NSSlider* slider = [NSSlider sliderWithValue:val minValue:0.0 maxValue:1.0 target:delegate action:@selector(onSliderChanged:)];
    slider.frame = NSMakeRect(24, y + 22, width - 48, 20);
    slider.continuous = YES;
    slider.tag = info.id;
    slider.autoresizingMask = NSViewWidthSizable;
    [parent addSubview:slider];
    [delegate.sliders addObject:slider];
}

static void buildParameterRows(
    NSView* parent,
    Steinberg::Vst::EditController* controller,
    Vst3PluginEditorDelegate* delegate) {
    if (!controller) return;
    int count = controller->getParameterCount();
    CGFloat width = parent.bounds.size.width;
    CGFloat y = 74.0;
    for (int i = 0; i < count; ++i) {
        Steinberg::Vst::ParameterInfo info;
        if (controller->getParameterInfo(i, info) != Steinberg::kResultTrue) continue;
        buildSingleRow(parent, controller, info, width, y, delegate);
        y += 56.0;
    }
}

static void buildFooter(NSView* parent) {
    CGFloat w = parent.bounds.size.width;
    CGFloat h = parent.bounds.size.height;
    NSTextField* footer = [NSTextField labelWithString:@"Preallocated Zero-Copy Shared Memory DSP"];
    footer.frame = NSMakeRect(24, h - 24, w - 48, 16);
    footer.alignment = NSTextAlignmentCenter;
    footer.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
    footer.textColor = [NSColor colorWithCalibratedWhite:0.4 alpha:1.0];
    footer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [parent addSubview:footer];
}

NSView* createCocoaFallbackView(
    NSView* parent,
    Steinberg::Vst::EditController* controller,
    const std::string& pluginName,
    Vst3PluginEditorDelegate** outDelegate) {
    auto container = [[Vst3FlippedView alloc] initWithFrame:parent.bounds];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.09 green:0.09 blue:0.11 alpha:1.0].CGColor;
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    auto delegate = [[Vst3PluginEditorDelegate alloc] init];
    delegate.controller = controller;
    delegate.sliders = [NSMutableArray array];
    delegate.valueLabels = [NSMutableArray array];
    if (outDelegate) *outDelegate = delegate;

    buildHeader(container, pluginName);
    buildParameterRows(container, controller, delegate);
    buildFooter(container);
    return container;
}
