// Copyright (c) 2025
// Header for embedded Flutter/Native view factory function
//
// Architecture & Synchronization Overview:
// In the Steinberg VST3 architecture, the `EditController` handles parameter
// management and UI creation (`createView`). When using Steinberg's proprietary
// VSTGUI framework, parameter changes from the host automatically propagate
// to controls. However, when embedding an OS-native view (such as macOS AppKit
// NSView, Windows HWND, or Linux X11/Wayland), Steinberg's `EditController`
// does not have a built-in mechanism to notify the native view.
//
// `IEmbeddedFlutterView` solves this:
// 1. Controller -> View: The controller implements `setParamNormalized` and
//    forwards incoming host/automation updates to `activeView_->updateParameter(id, value)`.
// 2. View -> Controller: User interactions in the native GUI call
//    `EditController::beginEdit`, `setParamNormalized`, `performEdit`, and `endEdit`,
//    which notify both the DAW automation queue and the real-time audio DSP thread.
// 3. Safe Lifecycles: An optional `IEmbeddedFlutterView** outViewPtr` holder ensures
//    neither the controller nor the view holds dangling pointers if either is closed first.

#pragma once

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/vsttypes.h"

namespace Steinberg {
    class IPlugView;

namespace Vst {
    class EditController;

    /// Interface implemented by native UI views (Cocoa/Win32/X11) to receive
    /// parameter updates directly from the VST3 EditController.
    class IEmbeddedFlutterView {
    public:
        virtual ~IEmbeddedFlutterView() = default;

        /// Called by EditController::setParamNormalized when a parameter is updated
        /// by the DAW host, preset loading, or parameter automation.
        ///
        /// Implementations should dispatch the update to the main UI thread.
        virtual void updateParameter(ParamID id, ParamValue value) = 0;

        /// Notifies the view that the parent EditController is being destroyed.
        /// The view must clear any references to the controller to prevent use-after-free.
        virtual void onControllerClosed() = 0;
    };

    /// Factory function that creates the platform-specific embedded plugin view.
    ///
    /// @param controller Pointer to the plugin's EditController.
    /// @param pluginName Display name of the plugin shown in the UI header.
    /// @param outViewPtr Optional pointer to the controller's active view holder.
    ///                   When provided, the view registers itself and automatically
    ///                   nullifies `*outViewPtr` when the view window is closed.
    /// @return A pointer to the newly created IPlugView instance.
    IPlugView* createEmbeddedFlutterView(
        EditController* controller,
        const char* pluginName,
        IEmbeddedFlutterView** outViewPtr = nullptr);
}
}